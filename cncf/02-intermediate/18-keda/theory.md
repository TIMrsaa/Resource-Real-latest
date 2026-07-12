# 이론 — 3컴포넌트, HPA와의 계약, activation, 스케일러, ScaledJob

> **🌱 17세 눈높이 비유: 도서관 사서와 자동 배치 시스템**
> - **HPA** = 기존 배치 규칙 — "대출 대기 인원 ÷ 사서 1인당 처리량"으로 필요한 사서 수를 계산. 단 **최소 1명은 항상 상주**해야 계산이 됩니다(0명이면 "인당 처리량"이 무의미)
> - **KEDA operator** = 새 관리자 — "SNS 문의, 이메일 대기, 예약 건수" 같은 **외부 신호**를 보고 있습니다
> - **metrics-adapter** = 통역사 — HPA가 "대기 인원이 몇이야?"라고 물으면 외부 신호를 숫자로 번역해 답합니다
> - **activation** = 사서가 0명일 때의 특별 규칙 — "문의가 1건이라도 오면 일단 1명 출근" (HPA는 이걸 못 합니다)
> - **콜드스타트** = 0명에서 1명이 출근하는 데 걸리는 시간(옷 갈아입고, 자리 정리하고...)
> - **ScaledJob** = 문의 하나당 임시직 한 명을 고용해 처리하고 퇴근시키기

---

## 1. 3컴포넌트와 데이터 흐름

```
                          ┌─ ScaledObject (CRD)
                          │
┌─────────────────┐   watch   ┌──────────────────┐
│ keda-operator   │◀──────────┤   ScaledObject   │
│  - 스케일러 폴링 │            └──────────────────┘
│  - activation   │                    │ 생성
│  - HPA 생성/관리 │───────────────────▶│
└────────┬────────┘             ┌──────▼──────┐
         │                      │  HPA (k8s)  │  ★ 스케일 계산은 여전히 HPA
         │                      └──────┬──────┘
         │                             │ external metrics API 질의
         │                      ┌──────▼───────────────┐
         └─────────────────────▶│ keda-metrics-adapter │──▶ 외부 소스(Kafka/SQS/Prometheus...)
                                 └──────────────────────┘
(+) keda-admission-webhooks: ScaledObject 검증(중복 대상, 잘못된 설정 차단)
```

| 컴포넌트 | 하는 일 |
|---|---|
| **operator** | ScaledObject watch, 스케일러 폴링(activation 판단), HPA 생성·삭제, 0↔1 전환 |
| **metrics-adapter** | External Metrics API(`external.metrics.k8s.io`) 서버 — HPA의 질의에 답합니다 |
| admission-webhooks | 설정 검증(같은 대상에 두 ScaledObject 등) |

**핵심 계약**: KEDA는 HPA를 만들고, HPA가 `1 ↔ maxReplicaCount` 구간의 스케일을 계산합니다. `0 ↔ 1`만 KEDA가 직접 합니다.

## 2. activation vs scaling — 두 개의 문턱

```yaml
triggers:
  - type: prometheus
    metadata:
      threshold: "100"              # ★ scaling: HPA의 target — 이 값으로 replicas 계산
      activationThreshold: "5"      # ★ activation: 이 값을 넘어야 0 → 1
```

```
metric = 0..5     → replicas 0 (비활성)          ← KEDA가 판단
metric = 5..∞     → 활성화 → HPA가 계산 시작
   desired = ceil(metric / threshold)   (HPA의 표준 공식)
   metric=1347, threshold=100  →  14 replicas

★ activationThreshold를 안 주면 기본 0 → 메트릭이 0보다 크면 즉시 활성
★ threshold는 "Pod 하나가 감당할 양" — 큐 길이 100이면 Pod 하나가 100개를 처리
```

`cooldownPeriod`(기본 300초): 마지막 활성 이후 이 시간이 지나야 0으로 내립니다(플래핑 방지).

## 3. 스케일러(트리거) — 60종 이상

| 분류 | 예 | 메트릭 |
|---|---|---|
| 큐·스트림 | Kafka(lag), RabbitMQ, SQS, Azure Queue, NATS JetStream | 미처리 메시지 수 |
| 메트릭 | **Prometheus**(임의의 PromQL!), Datadog, CloudWatch | 쿼리 결과 |
| DB | PostgreSQL, MySQL, MongoDB, Redis(list length) | 쿼리 결과 |
| 시간 | **cron** | 활성 구간 |
| 기타 | HTTP(add-on), S3, Elasticsearch, CPU/Memory | — |

```yaml
# Prometheus 스케일러 — 사실상 "무엇이든" 스케일 트리거가 됩니다
triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus:9090
      query: sum(rate(http_requests_total{app="api"}[2m]))
      threshold: "50"        # Pod 하나가 초당 50 요청 처리
```

### 인증 — TriggerAuthentication

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata: { name: kafka-auth }
spec:
  secretTargetRef:
    - { parameter: sasl, name: kafka-secret, key: sasl }
  # 또는 podIdentity: { provider: aws }   ← IRSA/Pod Identity (eks)
```

`ClusterTriggerAuthentication`으로 클러스터 전역 공유. **KEDA operator가 이 자격증명으로 외부 시스템을 폴링**합니다 — 즉 KEDA는 큐·DB·Prometheus에 접근 권한이 필요하고, 그것이 신뢰 경계입니다(07).

## 4. ScaledObject vs ScaledJob

| | ScaledObject | ScaledJob |
|---|---|---|
| 대상 | Deployment/StatefulSet/CR(scale 서브리소스) | Job 템플릿 |
| 모델 | 워커가 상주하며 큐를 소비 | 메시지(들)마다 Job 생성 |
| 종료 | Pod가 계속 삽니다 | 처리 후 Pod 종료 |
| 재시도 | 앱이 처리 | K8s Job의 backoffLimit |
| 적합 | 짧은 메시지 대량, 워커 재사용 | **긴 작업**(수 분~시간), 격리, 재시도 |
| 위험 | 처리 중 스케일다운 시 메시지 유실(graceful shutdown 필수) | Pod 생성 폭주(API 서버 부하) |

```yaml
kind: ScaledJob
spec:
  jobTargetRef: { template: {...} }
  pollingInterval: 30
  maxReplicaCount: 50
  scalingStrategy: { strategy: "accurate" }   # default | custom | accurate(대기 잡 고려)
  triggers: [{ type: aws-sqs-queue, ... }]
```

## 5. scale-to-zero의 물리학

```
0 → 1 지연 = pollingInterval(최대) + 스케줄 + 이미지 pull + 앱 부팅 [+ 노드 프로비저닝]
                 ↑ 기본 30초              ↑ 캐시 없으면 수십 초    ↑ Karpenter 1~2분

대응:
  - pollingInterval을 줄입니다 (외부 시스템 폴링 부하와 트레이드오프)
  - 이미지를 노드에 프리풀(DaemonSet) 또는 작은 이미지(cicd 04·19)
  - 앱 부팅 최적화 (JVM 워밍업 등)
  - 노드 여유를 확보 (overprovisioning Pod — 낮은 우선순위 더미)
  - ★ 사용자 대면 동기 경로에는 minReplicaCount ≥ 1
```

## 6. Karpenter와의 직렬 관계 (10의 복습, eks 17)

```
이벤트 → KEDA(operator+HPA) → replicas 증가 → Pod Pending(자원 부족)
                                                    ↓
                                            Karpenter가 Pending Pod의 요구를 보고 노드 생성
                                                    ↓
                                            스케줄 → 실행

진단 층:
  ① 스케일러가 신호를 못 읽음   → ScaledObject status, operator 로그, 인증
  ② metrics-adapter가 답 못 함  → kubectl get --raw /apis/external.metrics.k8s.io/...
  ③ HPA가 계산은 하나 안 늘림   → kubectl describe hpa (behavior, max, 조건)
  ④ Pod가 Pending              → 노드 층 (Karpenter·자원·taint)
★ "KEDA를 깔았는데 Pod가 안 뜬다"의 대부분은 ③ 또는 ④입니다
```

## 7. 운영 고려사항

```
폴링 부하: ScaledObject 수 × 트리거 수 ÷ pollingInterval = 외부 시스템 QPS
           수백 개의 ScaledObject가 같은 Prometheus를 초당 폴링하면? (11의 부하)
HPA 충돌: 같은 대상에 HPA를 직접 만들면 서로 싸웁니다 → admission이 막지만 확인 필요
paused:    keda.sh/paused-replicas 어노테이션으로 일시 고정 (배포·조사 중)
메트릭:    keda_scaler_errors_total, keda_scaler_metrics_value — 반드시 알람
fallback:  스케일러 실패 시 대체 replicas 지정(spec.fallback) — 외부 시스템 장애에 대한 방어
```

## 8. 소스/도구에서 확인하기

- KEDA: https://keda.sh/docs — scalers 카탈로그, ScaledJob, authentication
- External Metrics API: `kubectl get --raw /apis/external.metrics.k8s.io/v1beta1`
- HPA 알고리즘: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
- 10·eks 17 복습: 층 구분

## 요약 카드

| 질문 | 답 |
|------|----|
| KEDA와 HPA? | KEDA가 HPA를 **생성**하고, 스케일 계산은 HPA가 합니다(1↔max). 0↔1만 KEDA |
| 두 문턱? | activationThreshold(0→1) vs threshold(HPA의 target — replicas 계산) |
| 스케일 공식? | desired = ceil(metric / threshold) — 표준 HPA 알고리즘 |
| Prometheus 스케일러? | 임의의 PromQL이 트리거 — "무엇이든" 스케일 신호가 됩니다 |
| ScaledJob은 언제? | 긴 작업·격리·재시도가 필요할 때 (짧은 대량은 ScaledObject) |
| scale-to-zero 대가? | 콜드스타트 = 폴링 + 스케줄 + pull + 부팅 [+ 노드 생성] |
| 진단 4층? | 스케일러 → metrics-adapter → HPA → 노드(Karpenter) |
| 필수 방어? | fallback, keda_scaler_errors 알람, graceful shutdown |
