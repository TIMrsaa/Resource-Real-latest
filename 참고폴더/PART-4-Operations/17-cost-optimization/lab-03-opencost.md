# Lab 03 — OpenCost (NS / Workload 단위 비용 배분)

> **🌱 핵심 개념 미리보기**
> - **OpenCost**: K8s 의 비용을 Namespace/Pod/Label 단위로 배분하는 CNCF 프로젝트. KubeCost 의 오픈소스 코어.
> - **왜 필요한가**: AWS 청구서는 EC2/EBS 단위로 옴. "order 팀 vs payment 팀이 얼마 썼나" 는 청구서로 못 봄.
> - **데이터 소스**: Prometheus 의 사용량 메트릭(`container_cpu_usage_seconds_total` 등) + AWS 가격표 API.
> - **Allocation API**: `/allocation` 엔드포인트가 시간 윈도우/aggregate 차원별 비용 JSON 반환.
> - **공유 자원 처리**: kube-system, monitoring 같은 공유 NS 비용을 다른 NS 에 분배하는 옵션 존재.

## 1. 사전 — Prometheus 떠 있어야 함

```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus
```

## 2. OpenCost 설치

```bash
helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm repo update

helm install opencost opencost/opencost \
  -n opencost --create-namespace \
  --set opencost.exporter.defaultClusterId=eks-study \
  --set opencost.prometheus.internal.enabled=false \
  --set opencost.prometheus.external.enabled=true \
  --set opencost.prometheus.external.url="http://kps-kube-prometheus-stack-prometheus.monitoring:9090"

kubectl get pods -n opencost
```

기대:
```
NAME                        READY   STATUS    RESTARTS   AGE
opencost-xxx                2/2     Running   0          1m
```

> **🧠 OpenCost 가 가격을 어떻게 계산하나**
> 1. **AWS Pricing API** (기본): 인스턴스 타입/리전별 on-demand 가격을 주기적으로 가져옴.
> 2. **Spot 가격**: spot data feed S3 버킷 연동 옵션 (정확한 spot 비용 반영).
> 3. **사용자 정의 가격**: 온프레미스/하이브리드 환경에선 `customPricing` 으로 시간당 비용 지정.
>
> Pod 비용 = (요청한 CPU · 시간 × CPU 단가) + (요청 메모리 · 시간 × 메모리 단가). requests 가 0 이면 비용 0 으로 잡힘.

## 3. UI 접근

```bash
kubectl port-forward -n opencost svc/opencost 9090:9090 &
```

> OpenCost UI 는 9090 (Prometheus 와 충돌 주의 — 다른 포트로 방향 전환 또는 백그라운드 정지)

```bash
kubectl port-forward -n opencost svc/opencost 9003:9003 &
```

브라우저: http://localhost:9003

탭들:
- **Cost Allocation** — Namespace / Pod / 라벨 단위 비용
- **Assets** — Node / 디스크 비용
- **Savings** — 절감 추천

## 4. NS 별 비용 (CLI)

OpenCost 의 API:
```bash
curl -s 'http://localhost:9003/allocation' \
  --data-urlencode 'window=24h' \
  --data-urlencode 'aggregate=namespace' \
  -G | jq '.data[0] | to_entries[] | {ns: .key, cost: .value.totalCost}' | head -20
```

기대 (예시):
```json
{"ns":"kube-system","cost":2.45}
{"ns":"order","cost":1.20}
{"ns":"monitoring","cost":3.10}
```

> **🧠 `aggregate` 차원 종류**
> - `namespace` / `controller` / `pod` / `node` / `cluster`
> - `label:<key>` — 임의 라벨로 그룹 (예: `label:team`, `label:env`)
> - 콤마로 다중: `aggregate=namespace,label:team` → NS × team 매트릭스
>
> 같은 NS 의 여러 Deployment 분리해 보려면 `aggregate=controller` 또는 `controller,namespace`.

## 5. 시간대별 비용 추이

```bash
curl -s 'http://localhost:9003/allocation' \
  --data-urlencode 'window=7d' \
  --data-urlencode 'aggregate=namespace' \
  --data-urlencode 'step=24h' \
  -G | jq '.data | length'
```

→ 일 단위로 7개 결과.

## 6. 라벨 기반 비용 (팀 단위)

Pod 에 `team=alpha` 라벨이 붙어 있다면:
```bash
curl -s 'http://localhost:9003/allocation' \
  --data-urlencode 'window=24h' \
  --data-urlencode 'aggregate=label:team' \
  -G | jq '.data[0]'
```

→ 팀 별 비용.

> **🧠 OpenCost vs KubeCost 차이**
> - **OpenCost**: 100% 오픈소스 (Apache 2.0). 핵심 비용 배분 엔진 + 기본 UI/API.
> - **KubeCost**: OpenCost 위에 상용 기능 (멀티 클러스터 통합 뷰, 거버넌스 알람, 더 정교한 Savings 추천, RBAC 등).
> - 학습/단일 클러스터엔 OpenCost 충분. 여러 팀/멀티 클러스터 거버넌스 필요하면 KubeCost.

## 7. Grafana 대시보드 import (선택)

OpenCost 는 Prometheus 메트릭으로도 노출 → Grafana 에서 시각화.

ID **9837** (OpenCost 공식 대시보드) import.

> **🧠 비용 배분의 한계 — Idle Cost 와 공유 비용**
> 노드 1대가 $1 인데 그 위 Pod requests 합계가 $0.7 만 잡히면 차액 $0.3 = **idle cost** (노드 빈자리 비용).
> OpenCost 는 idle 을 별도 차원으로 보여주거나 NS 비례 배분 가능.
> kube-system / 모니터링 같은 **공유 NS** 비용도 사용량 비례로 다른 NS 에 분배(`shareIdle`, `shareNamespaces`)할 수 있음 — 팀 청구서 만들 때 핵심.

## 8. 정리

```bash
helm uninstall opencost -n opencost
kubectl delete ns opencost
```

## 학습 확인

- OpenCost 가 가격 정보를 어디서 가져오나?
- 같은 NS 의 여러 Deployment 비용을 분리해 보려면 어떤 aggregate?
- KubeCost 와 OpenCost 의 차이는?

다음: [quiz.md](./quiz.md)
