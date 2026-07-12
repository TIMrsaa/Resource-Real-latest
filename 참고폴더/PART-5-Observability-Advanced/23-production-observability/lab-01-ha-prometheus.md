# Lab 01 — Prometheus HA + remote_write

> **🌱 왜 HA Prometheus 가 필요한가?**
> 단일 Prometheus 의 위험:
> - **Pod 죽으면** = 그 시간 동안 메트릭 손실 + 알람 평가 중단
> - **노드 NotReady** = Prometheus 도 같이 죽음 → 같은 알람 못 받음 (체이스 함정)
>
> **HA 패턴**: 같은 설정의 Prometheus 2개 동시 실행. 둘 다 같은 target 을 scrape.
> = 하나 죽어도 다른 하나가 계속 평가/통보.
>
> **함정**: 두 Prometheus 가 **같은 알람을 두 번** 통보 → Alertmanager 가 dedup (같은 라벨 set 알람은 묶음).

## 1. 현재 replicas 확인

```bash
kubectl get prometheus -n monitoring kps-kube-prometheus-stack-prometheus -o yaml | yq '.spec.replicas'
```

기본 1.

## 2. HA — replicas 2 로 변경

```bash
helm upgrade kps prometheus-community/kube-prometheus-stack \
  --reuse-values \
  -n monitoring \
  --set prometheus.prometheusSpec.replicas=2 \
  --set prometheus.prometheusSpec.replicaExternalLabelName=replica
```

`replicaExternalLabelName: replica` 가 핵심 — Prometheus 별로 `replica=A`, `replica=B` 같은 라벨 자동 부여.

> **🧠 `replicaExternalLabelName` 의 두 가지 역할**
> 1. **Alertmanager dedup**: 두 Prom 가 같은 알람 보낼 때 `replica` 라벨만 다름. AM 의 dedup 로직이 "다른 라벨은 동일 + replica 만 다름 = 같은 알람" 인식해 1번만 발송.
> 2. **remote_write/Thanos dedup**: 외부 저장소도 `replica` 라벨로 두 Prom 의 중복 데이터 식별 → 한 쪽만 저장.
>
> 만약 이 라벨 안 주면 두 Prom 데이터가 외부에서 **합쳐져 2배** 처럼 보임 → RPS 두 배로 잘못 측정.

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
```

기대:
```
prometheus-kps-kube-prometheus-stack-prometheus-0   2/2   Running
prometheus-kps-kube-prometheus-stack-prometheus-1   2/2   Running
```

> **🧠 Prometheus 가 StatefulSet 인 이유**
> StatefulSet → Pod 마다 영속 PVC + 안정 이름 (`prometheus-...-0`, `-1`).
> 이유:
> - 각 Pod 가 자기 TSDB 디스크 가져야 (Deployment 면 재시작마다 데이터 손실)
> - replica 식별자 (`STATEFULSET_ORDINAL_NUMBER`) 로 자기가 A 인지 B 인지 판단

## 3. 두 Prometheus 가 같은 데이터 갖는지 확인

```bash
# Pod 0
kubectl port-forward -n monitoring prometheus-kps-...-0 9091:9090 &
# Pod 1
kubectl port-forward -n monitoring prometheus-kps-...-1 9092:9090 &

curl -sG http://localhost:9091/api/v1/query --data-urlencode 'query=up' | jq '.data.result | length'
curl -sG http://localhost:9092/api/v1/query --data-urlencode 'query=up' | jq '.data.result | length'
```

두 결과 비슷한 시계열 수.

> **🧠 "비슷하지만 정확히 같지 않음"**
> 두 Prom 는 **각자 독립적으로 scrape** → 시간이 1~2초 어긋날 수 있음.
> 같은 시계열이지만 데이터 포인트 시각이 다름 → 같은 PromQL 결과의 숫자가 살짝 다를 수 있음.
>
> 운영 영향:
> - 알람 평가는 둘 다 같은 결론 → OK
> - 하지만 정확한 숫자가 필요한 dashboard 는 한 Prom 만 봐야 (round-robin 시 jitter)

## 4. Grafana 가 두 source 보면 중복

대시보드의 패널이 두 시리즈 (replica=A, replica=B) 로 분리됨 → 의도 X.

> **🧠 왜 시리즈가 분리되나?**
> Grafana 의 PromQL 쿼리 결과 = 시계열 단위. `replica=A` 와 `replica=B` 가 다른 라벨 → 다른 시계열 → 그래프에 두 줄.
>
> 해결책:
> - **PromQL 에서 sum without(replica)** — `replica` 라벨 무시
> - **Service 가 round-robin** — 한 번에 한 Prom 만 응답 (라벨 일관)
> - **Thanos Querier** — dedup 처리 (replica 인식해 한 시리즈로)

## 5. 해결 방법 1 — service 가 round-robin 으로 한 Prom 만 골라줌

`kps-kube-prometheus-stack-prometheus` 라는 Service 가 두 Pod 의 selector 로 매칭. 하지만 round-robin 이라 일관 X.

→ 이 방식은 단순 HA 만 (어느 Prom 이 죽어도 다른 게 응답).

> **🧠 round-robin 의 한계 — 시계열 jitter**
> 같은 PromQL 을 30s 마다 호출 → 매번 다른 Pod 응답.
> 두 Pod 의 데이터가 1초 어긋나면 그래프가 톱니처럼 진동.
> = 사람이 보면 "이상한 데이터" 처럼 보임.
>
> 그래서 단순 HA 는 "Pod 가용성" 만 해결, "데이터 일관성" 은 안 됨.
> 진짜 운영급은 Thanos / Cortex / Mimir / AMP 의 dedup proxy 필요.

## 6. 해결 방법 2 — Thanos sidecar / 또는 dedup proxy

각 Prom 옆에 Thanos sidecar:
```yaml
prometheus.prometheusSpec:
  thanos:
    image: quay.io/thanos/thanos:v0.36.0
    objectStorageConfig: ...
```

Thanos Querier 가 두 sidecar 를 통합 → 중복 자동 dedup (replica external label 사용).

> **🧠 Thanos sidecar 의 두 가지 책임**
> 1. **Block 업로드**: Prometheus 가 2시간마다 만드는 TSDB block 을 S3 에 업로드 → 장기 저장
> 2. **gRPC API**: Thanos Querier 가 sidecar 통해 Prom 의 head 데이터 + S3 의 옛 데이터 통합 쿼리
>
> Thanos 아키텍처:
> ```
>   각 Prom + sidecar (실시간) → S3 (장기) ← Store Gateway ← Querier
>                                                              ↑
>                                                      Grafana 가 쿼리
> ```
> 결과: 무한 retention + dedup + multi-cluster 통합.

## 7. remote_write 로 외부 저장소 push

```yaml
prometheus.prometheusSpec:
  remoteWrite:
    - url: https://central-storage.example.com/api/v1/write
      queueConfig:
        maxSamplesPerSend: 1000
        maxShards: 200
        capacity: 2500
```

각 클러스터 Prom 이 자기 데이터를 push → 중앙에서 통합.

> **🧠 remote_write vs Thanos sidecar 비교**
> | | remote_write | Thanos sidecar |
> |--|-------------|----------------|
> | 데이터 흐름 | push (실시간) | block upload (2h마다) |
> | 외부 저장소 | TSDB-호환 (Mimir, Cortex, AMP) | S3 (object storage) |
> | 중복 처리 | 외부 저장소가 알아서 | Querier 의 dedup |
> | 운영 복잡도 | 낮음 | 중 (sidecar + Querier + Store) |
> | AWS 매니지드 | AMP | 자체 구축 |
>
> **결론**: AWS 환경 → AMP (remote_write). 자체 구축 → Mimir 또는 Thanos.

## 8. 학습 환경에서는

학습 클러스터 1개라 HA 의 가치 적음. 대신 Thanos / AMP 의 학습 의미가 큼 → 다음 lab.

## 9. 원복

```bash
helm upgrade kps prometheus-community/kube-prometheus-stack \
  --reuse-values \
  -n monitoring \
  --set prometheus.prometheusSpec.replicas=1
```

> **🧠 원복 시 데이터는?**
> StatefulSet 의 replica 를 2 → 1 줄이면 Pod-1 종료, **PVC 는 유지** (데이터 보존).
> 다시 2 로 늘리면 Pod-1 가 같은 PVC 마운트 → 데이터 살아남.
>
> 완전 정리는 PVC 도 삭제: `kubectl delete pvc prometheus-...-1 -n monitoring`. 단, 운영에선 신중 (메트릭 영구 손실).

## 학습 확인

1. `replica` external label 의 역할은?
2. 두 Prom 이 정확히 같은 시각에 같은 target 을 scrape 하는가? 차이가 만드는 효과?
3. Thanos sidecar 의 두 가지 책임은?

> **힌트**:
> 1. Alertmanager / 외부 저장소가 두 Prom 데이터를 dedup 식별. 라벨 안 주면 같은 알람 2번 / 데이터 2배 측정.
> 2. 아니. 각 Prom 독립 scrape → 1~2초 어긋남. round-robin 쿼리 시 그래프 jitter. dedup 가 필요한 이유.
> 3. (a) Prometheus block 을 S3 업로드 (장기 저장), (b) gRPC API 로 Thanos Querier 가 head 데이터 접근.

다음: [lab-02-amp.md](./lab-02-amp.md)
