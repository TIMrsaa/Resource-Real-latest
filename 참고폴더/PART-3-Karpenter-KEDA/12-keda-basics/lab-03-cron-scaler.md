# Lab 03 — Cron 트리거 + Scale-to-Zero

## 학습 확인 포인트

- [ ] Pod 가 0 인 상태를 봤다 (HPA 만으로는 불가능)
- [ ] Cron 시간이 되면 자동으로 Pod 가 켜짐
- [ ] 시간 끝나면 다시 0 으로

> **🌱 핵심 개념 미리보기**
> - **scale-to-zero**: KEDA 의 시그니처 기능. HPA 는 최소 1, KEDA 는 0 까지 가능.
> - **cron trigger**: 시간 기반 스케일링. start/end 두 개의 cron 표현식.
> - **timezone**: KEDA 의 cron 은 default UTC. `Asia/Seoul` 등 명시 권장.
> - **desiredReplicas**: cron 활성 구간 동안 유지할 Pod 수.
> - **다중 trigger**: cron + cpu 결합 가능 → max 값 사용 (가장 큰 desired 선택).

## 1. 적용

```bash
kubectl apply -f manifests/cron-scaler.yaml
kubectl get deploy cron-demo            # replicas=0
kubectl get scaledobject cron-demo
```

## 2. 처음엔 0 인지 확인

```bash
kubectl get pods -l app=cron-demo
```

기대: `No resources found`. 노드 자원 0 점유.

> **🧠 KEDA 가 0 으로 만드는 메커니즘**
> ScaledObject 가 활성화되면 KEDA 가 외부 HPA 를 만들고, replicas 를 외부 메트릭 기반으로 관리.
> `minReplicaCount: 0` 일 때 trigger 가 inactive → KEDA 가 직접 Deployment 의 `spec.replicas=0` 설정 (HPA 우회).
> 다시 active 되면 KEDA 가 1 로 복귀시키고 그 후엔 HPA 가 desired 까지 늘림. = 두 단계 메커니즘.

## 3. Cron 시간 도래

이 ScaledObject 의 `start: "*/5 * * * *"` 는 매 5분의 0초마다 트리거. 5분 단위로 watching:
```bash
watch -n5 'date; kubectl get deploy cron-demo; kubectl get pods -l app=cron-demo'
```

매 5분의 0초 ~ 1분 까지 (즉 각 5분 cycle 의 첫 1분 동안) Pod 가 3개로 켜졌다가 다시 0으로.

> **🧠 cron trigger 의 동작 방식**
> KEDA 는 매 polling interval(기본 30초)마다 현재 시각이 start~end 사이인지 평가.
> start 시각 즉시 켜지는 게 아니라 **다음 poll** 에서 감지 → 최대 30초 지연 가능.
> 정확한 sharp on/off 가 필요하면 polling interval 을 줄이거나 cron 을 좀 더 일찍 시작하는 식의 보정.

## 4. 다른 사용 사례

### 4.1 운영 시간 외 비활성

```yaml
triggers:
  - type: cron
    metadata:
      timezone: Asia/Seoul
      start: "0 9 * * mon-fri"      # 평일 09:00 켜짐
      end: "0 18 * * mon-fri"        # 18:00 꺼짐
      desiredReplicas: "10"
```

→ 업무 시간엔 10개, 그 외엔 0.

### 4.2 야간 배치 작업 시간 고정

```yaml
triggers:
  - type: cron
    metadata:
      start: "0 2 * * *"          # 매일 02:00
      end: "0 4 * * *"             # 04:00
      desiredReplicas: "20"
```

## 5. 다중 트리거 결합

```yaml
triggers:
  - type: cron
    metadata: {start: "0 9 * * mon-fri", end: "0 18 * * mon-fri", desiredReplicas: "5"}
  - type: cpu
    metricType: Utilization
    metadata: {value: "70"}
```

→ 업무 시간엔 항상 5개 + CPU 70% 넘으면 더 늘림.

> **🧠 다중 trigger 의 결합 규칙 (max)**
> ScaledObject 의 trigger 가 여러 개일 때 KEDA 는 각 trigger 의 desired replicas 를 계산 → **가장 큰 값 선택**.
> 즉 cron 5 + cpu 8 이면 8. cron 0 + cpu 0 이면 0 → minReplicaCount 따름.
> "둘 다 만족" 같은 AND 로직은 없음. OR/MAX 만 가능 → 정책 설계 시 주의.

## 6. 정리

```bash
kubectl delete -f manifests/cron-scaler.yaml
```

## 학습 확인 질문

1. KEDA 가 Pod 를 0 으로 줄이는 메커니즘은?
2. `cooldownPeriod` 가 의미하는 것은?
3. 두 cron trigger (start1+end1, start2+end2) 를 동시에 두면?

다음: [lab-04-prometheus-scaler.md](./lab-04-prometheus-scaler.md)
