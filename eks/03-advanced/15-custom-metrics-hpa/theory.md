# 이론 — 메트릭 API 3형제, 어댑터, 그리고 target 산정법

> **🌱 17세 눈높이 비유: 카페의 직원 충원 기준**
> 매니저(HPA)가 아르바이트를 더 부를지 정합니다:
> - **CPU 기준** = "직원 이마의 땀을 보고 충원" — 땀은 손님이 몰리고 **한참 뒤에** 납니다. 게다가 재료 기다리느라 한가한(IO-bound) 직원은 땀이 안 나는 채로 주문이 밀립니다
> - **RPS 기준** = "문으로 들어오는 손님 수를 보고 충원" — 원인을 직접 봅니다. "직원 1명당 손님 12명이 한계던데(13에서 측정), 9명 넘으면 부르자"
> - 문제는 매니저가 **자기 계기판(메트릭 API)에 있는 숫자만** 본다는 것 — 손님 수를 계기판에 올려주는 장치(어댑터)가 필요합니다
> - **KEDA** = 손님 수뿐 아니라 배달앱 주문 큐, 예약 문자까지 보고 부르는 만능 비서 — 심지어 손님 0명이면 직원을 0명까지 줄입니다

---

## 1. HPA 복습 한 줄과 공식 (k8s 26)

```
desiredReplicas = ceil( currentReplicas × 현재값 / 목표값 )
```

HPA는 이 산수를 15초마다 돌리는 단순한 컨트롤러입니다 — 지능은 **어떤 "현재값"을 주느냐**에 있습니다. CPU를 주면 CPU 스케일러가, RPS를 주면 RPS 스케일러가 됩니다.

## 2. 메트릭 API 3형제 — HPA가 보는 세 개의 창

| API | 서빙하는 자 | 내용 | HPA 문법 |
|-----|------------|------|---------|
| `metrics.k8s.io` | metrics-server | CPU/메모리 (kubelet 집계) | `type: Resource` |
| `custom.metrics.k8s.io` | **어댑터** (Prometheus Adapter 등) | 클러스터 안 워크로드의 메트릭 (Pod RPS…) | `type: Pods` / `Object` |
| `external.metrics.k8s.io` | 어댑터 (KEDA 등) | 클러스터 **밖** 신호 (SQS 길이, CloudWatch…) | `type: External` |

세 API 모두 aggregated API(k8s 29의 APIService 등록) — `kubectl get --raw /apis/custom.metrics.k8s.io/...`로 직접 조회 가능하다는 것이 디버깅의 열쇠.

## 3. 경로 A 해부 — Prometheus + Adapter

```
앱 /metrics (http_request_duration_seconds_count 등 카운터)
 → Prometheus가 scrape (Pod annotation 발견)
 → Adapter가 규칙으로 번역:
     seriesQuery: 어떤 시계열을    (http_request_duration_seconds_count)
     metricsQuery: 어떻게 가공해   (rate(...[1m]) — 카운터→초당 증가율)
     name: 무슨 이름으로            (http_requests_per_second)
 → custom.metrics.k8s.io 서빙 → HPA(type: Pods, averageValue)
```

핵심 개념 두 개:

- **카운터와 rate**: 앱은 "누적 요청 수"(단조 증가)를 내고, RPS는 그것의 **시간당 미분**(`rate[1m]`)입니다 — 어댑터 규칙의 절반은 이 변환
- **averageValue**: `type: Pods`의 목표는 **Pod당 평균** — 총 RPS가 아니라 "Pod 하나가 감당하는 양"이라서 replicas 산수와 자연히 맞물립니다

## 4. 경로 B 해부 — KEDA

```
ScaledObject (CRD) ── KEDA operator가 읽고 ──▶ HPA를 대신 생성/관리
   trigger: prometheus / aws-sqs / cloudwatch / cron / kafka ... (50+ scaler)
   minReplicaCount: 0   ← HPA 단독으론 불가능한 scale-to-zero
```

- KEDA는 HPA의 **대체가 아니라 포장**입니다 — 내부적으로 HPA를 만들고, 자신이 external metrics 어댑터 역할을 합니다
- **scale-to-zero**: 0→1은 HPA가 아닌 KEDA 자신이(activation threshold), 1→N은 HPA가 담당. 단 HTTP 서비스의 0은 "첫 요청을 받을 자가 없다"는 뜻 — 큐 기반 워커에 어울리고, HTTP는 별도 add-on 영역
- 어댑터는 클러스터에 **하나만**: Prometheus Adapter와 KEDA를 병존시킬 때 external API 충돌에 주의

## 5. 선택 기준

| 상황 | 답 |
|------|----|
| 이미 Prometheus 운영, HPA 문법 유지 | Adapter |
| 이벤트 소스가 다양(SQS/Kafka/cron), scale-to-zero 욕구 | KEDA |
| CloudWatch 메트릭(ALB RequestCountPerTarget 등)으로 직접 | KEDA cloudwatch scaler (12·14와 접점) |
| 학습 목적 (부품이 보여야 함) | Adapter 먼저 (이 모듈의 순서) |

## 6. target 산정 — 13의 보고서에서 숫자 가져오기

```
Pod당 무릎 = 무릎 rps ÷ 측정 시 replicas        (13 lab-01: 예. 900÷2 = 450)
HPA target(averageValue) = Pod당 무릎 × 0.7     (예. ≈ 300)
maxReplicas = 예상 피크 rps ÷ target + 여유      (예. 3000÷300 → 10 +2)
```

왜 70%인가: HPA 반응(메트릭 지연 15~60s + Pod 기동 시간) 동안 **초과분을 흡수할 쿠션**입니다. Pod 기동이 느릴수록(이미지 큼, 워밍업) 쿠션을 키웁니다 — 그 시간 동안은 기존 Pod들이 무릎 위에서 버텨야 하니까.

## 7. 흔들림 방지 — behavior (k8s 26의 심화)

RPS는 CPU보다 출렁입니다 — 그대로 반응하면 flapping(늘렸다 줄였습니다)이 됩니다:

```yaml
behavior:
  scaleUp:   { stabilizationWindowSeconds: 0,  policies: [{type: Percent, value: 100, periodSeconds: 30}] }  # 빠르게
  scaleDown: { stabilizationWindowSeconds: 300, policies: [{type: Pods, value: 1, periodSeconds: 60}] }       # 천천히
```

원칙: **증설은 민첩하게, 감축은 의심하며** — 늘리기 실패의 비용(유저 오류)이 줄이기 지연의 비용(약간의 과잉)보다 큽니다.

## 8. 소스/도구에서 확인하기

- Prometheus Adapter 규칙 문법: https://github.com/kubernetes-sigs/prometheus-adapter/blob/master/docs/config.md
- KEDA scalers 목록: https://keda.sh/docs/latest/scalers/
- HPA 알고리즘 원문: https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#algorithm-details
- 코드: `pkg/controller/podautoscaler/` (kubernetes/kubernetes) — replica 계산기 `replica_calculator.go`

## 요약 카드

| 질문 | 답 |
|------|----|
| CPU 스케일링의 두 구멍? | 후행(원인이 아닌 결과) + 간접(IO-bound엔 무감각) |
| HPA가 보는 창 3개? | metrics.k8s.io / custom(어댑터) / external(어댑터) |
| 어댑터의 일? | Prometheus 시계열을 rate 가공해 메트릭 API로 서빙 |
| KEDA의 정체? | HPA를 생성·관리하는 포장 + 50개 스케일러 + scale-to-zero |
| target 산정? | (무릎÷replicas)×0.7 — 13의 측정이 근거 |
| behavior 원칙? | 증설 민첩, 감축 신중 (5분 안정화 창) |
