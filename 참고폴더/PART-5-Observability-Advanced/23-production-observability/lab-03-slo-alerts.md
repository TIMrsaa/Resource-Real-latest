# Lab 03 — Multi-Burn-Rate SLO Alert

> **🌱 SLO 와 Burn Rate 가 뭔가?**
> - **SLI** (Service Level Indicator): 측정값 — "성공한 요청 / 전체 요청"
> - **SLO** (Service Level Objective): 목표 — "99.9% 가 성공해야"
> - **Error Budget**: 허용 실패량 — "0.1% = 30일 중 43.2분"
> - **Burn Rate**: budget 소진 속도 — "1시간에 budget 의 2% 소진 = burn rate 14.4"
>
> **왜 단순 임계값 (5% 에러) 보다 burn rate 가 좋은가?**
> 단순: "에러율 > 5% 면 알람" → 1분 spike 도 알람 (false positive), 큰 사고 (50% 5분) 도 평균 낮으면 놓침.
> Burn rate: **얼마나 빨리** budget 을 태우는지 → 운영적 의미 있음 (잔여 budget 시각화).
>
> **multi-burn-rate** = fast (5m + 1h) + slow (30m + 6h) 동시 만족 → 일시 spike 와 큰 사고 모두 잡되 false positive 줄임.

## 1. SLO 정의

order-service 의 가용성 SLO:
- **Target**: 99.9% (30일 rolling window)
- **Error Budget**: 0.1% = 30일 × 1440분 × 0.001 = 43.2 분

이 budget 을 "얼마나 빠르게" 소진하는지 → burn rate.

> **🧠 SLO target 선택 가이드**
> | 서비스 등급 | SLO | 30일 budget |
> |-----------|-----|-------------|
> | Tier 1 (결제, 인증) | 99.99% | 4.3분 |
> | Tier 2 (핵심 비즈니스) | 99.9% | 43분 |
> | Tier 3 (내부 도구) | 99.5% | 3.6시간 |
> | Tier 4 (실험/베타) | 99.0% | 7.2시간 |
>
> **함정**: 99.999% (5-nine) 는 마케팅 카피 — 실제 운영은 ms 단위 응답, 24/7 즉시 대응 필요. SRE 인력/비용 폭증.
> 대부분 99.9% 가 황금 비율 — 비용 합리적 + 사용자 만족.

## 2. SLO Recording + Alert Rule 적용

```bash
kubectl apply -f manifests/slo-rules.yaml
kubectl get prometheusrule -n monitoring order-service-slo
```

> **🧠 SLO 를 recording rule 로 사전 계산하는 이유**
> Burn rate 계산은 비싼 PromQL (여러 윈도우 + ratio + multiplication).
> 매 알람 평가마다 = Prometheus CPU 부담.
>
> 패턴:
> 1. **SLI recording**: `sli:order:availability:ratio_5m` (5분 평균 성공률)
> 2. **Burn rate recording**: `slo:order:burn_rate:5m_1h` (5m / 1h 결합 burn rate)
> 3. **Alert**: `slo:order:burn_rate:5m_1h > 14.4` ← 단순 비교만
>
> 분리 시 Grafana 에서도 같은 이름으로 즉시 시각화 가능.

## 3. 인위적으로 5xx 발생시키기

order-service 의 일부 path 에 의도적으로 5xx 응답하게:
```bash
# (현재 order-service 는 정상 응답만 함. 시뮬레이션:)
# 가짜 5xx 메트릭 push (Pushgateway 사용 또는 메트릭 직접 주입은 어려움)
# 대신 부하를 많이 줘서 OOM/Throttling 으로 5xx 유발
```

또는 메트릭 직접 manipulation 어려우니 **alert rule 을 임시로 임계 낮춤**:
```bash
kubectl patch prometheusrule -n monitoring order-service-slo --type='json' -p='[
  {"op":"replace","path":"/spec/groups/1/rules/0/expr","value":"vector(1)"}
]'
```

→ 항상 true → 즉시 fire 시작.

> **🧠 `vector(1)` 트릭**
> PromQL 에서 `vector(1)` = 항상 1 인 instant vector.
> alert expr 에 넣으면 = "조건 항상 true" → 즉시 firing.
>
> 학습용 알람 동작 검증의 표준 패턴. 운영에선 절대 X (실제 알람과 혼동).
> 실험 후 즉시 원복 필수.

## 4. Alert 동작 확인

http://localhost:9090/alerts → `OrderServiceSLOBurnRateFast` 가 `Pending` → 2분 후 `Firing`.

> **🧠 Pending → Firing 의 시간 측정**
> alert rule 의 `for: 2m` = "조건이 2분간 지속되어야 firing".
> Prometheus 가 evaluation interval (보통 30s) 마다 평가 → 4번 연속 true 면 Firing.
>
> 디버깅 시: /alerts 페이지에서 Active since 시각 확인 → for: 시간 더한 후 firing 예상.

## 5. Burn rate 계산 이해

```
SLO target = 99.9% (30d)
Error budget = 0.1%

Fast burn:
  1시간 안에 budget 의 2% 소진하면 fast
  budget burn rate = 14.4 (= 30d / 30d × 1/720 hour × 2%) — 단위가 budget/hour
  실제 error rate = 14.4 × 0.001 = 0.0144 = 1.44%

Slow burn:
  6시간 안에 budget 의 5% 소진
  burn rate = 1 (= 30d × 1/180 day × 5%)
  실제 error rate = 1 × 0.001 = 0.001 = 0.1%
```

이 값은 Google SRE Workbook 의 multi-burn-rate 공식. 다른 SLO 면 다른 값.

> **🧠 Burn rate 14.4 의 직관적 의미**
> "이 속도로 계속하면 budget 을 1/14.4 기간에 다 태움" = "30일 budget 을 30/14.4 ≈ 2일에 소진".
> = "지금 같은 에러율이 2일간 지속되면 SLO 위반".
>
> 1 시간 윈도우의 fast burn = "1시간 동안 14.4× 빠르게 태우는 중" → page 즉시 (위급).
> 6시간 윈도우의 slow burn = "6시간 누적 1× 속도로 태우는 중" → ticket (느린 누수).
>
> **threshold 수치 유도**:
> ```
>   1h 윈도우 + 2% budget 소진 허용 → burn rate 14.4
>   6h 윈도우 + 5% budget 소진 허용 → burn rate 6
>   24h 윈도우 + 10% budget 소진 허용 → burn rate 3
>   72h 윈도우 + 10% budget 소진 허용 → burn rate 1
> ```
> Google SRE Workbook Chapter 5 의 표 그대로.

## 6. 두 burn rate 가 동시 만족 (and) 인 이유

- Fast 만 있으면: 1분 spike 후 정상 복귀해도 alert
- Slow 만 있으면: 큰 사고 (50% error 5분간) 도 평균이 낮아 잡지 못함
- **둘 다**: 5분 평균 + 1시간 평균 모두 임계 → 진짜 sustained 문제

> **🧠 "5m AND 1h" 의 디테일**
> Fast burn alert:
> ```promql
> (slo:burn_rate:5m  > 14.4) and (slo:burn_rate:1h > 14.4)
> ```
>
> 짧은 윈도우 (5m) = "지금 빠르게 태움?" — 즉시성
> 긴 윈도우 (1h) = "꽤 오래 지속됨?" — 진성성
>
> **둘 다 OR 가 아니라 AND**:
> - OR: 둘 중 하나만 만족 → false positive (1분 spike 도 5m 만족)
> - AND: 둘 다 만족 → 1분 spike 는 1h 가 평균 내려서 미만족 → 무시
>
> 결과: noise 줄이면서 실제 사고 놓치지 않음.

## 7. SLO Dashboard

Grafana 에서 변수 + 패널:
- Stat: Current SLO compliance (`sli:order_service_availability:ratio_30d`)
- Time series: Error budget remaining over time
- Burn rate gauge

> **🧠 SLO 대시보드 표준 패널**
> | 패널 | PromQL (개념) | 시각화 |
> |-----|--------------|--------|
> | 현재 SLO | `1 - error_rate_30d` | Stat (큰 숫자, 99.95%) |
> | Budget 남은량 | `(error_budget - errors_30d) / error_budget` | Gauge (100% → 0%) |
> | Burn rate (현재) | `burn_rate_1h` | Stat with thresholds (>14.4 빨강) |
> | Burn rate 추이 | `burn_rate_1h` over time | Time series |
> | Active alerts | `ALERTS{alertname=~"...SLO..."}` | Table |
>
> 운영팀이 한눈에 "지금 budget 얼마 남았나" 파악 → 배포/실험 결정 근거.

## 8. 원복

```bash
kubectl apply -f manifests/slo-rules.yaml    # 원래대로
```

## 학습 확인

1. SLO 99.9% 와 99.99% 의 budget 차이는?
2. multi-burn-rate 가 single-rate alert 보다 좋은 두 가지는?
3. SLO 가 너무 엄격하면 어떤 부작용?

> **힌트**:
> 1. 99.9%=43min/30d, 99.99%=4.3min/30d. 10배 차이 — 운영 부담 / 인프라 비용 / SRE 인력 폭증.
> 2. (a) false positive 감소 (일시 spike 무시), (b) 큰 사고 놓치지 않음 (slow burn). 단순 5% 임계는 둘 다 못 함.
> 3. budget 즉시 소진 → 항상 firing → alert fatigue (다 무시), 실험/배포 위축, 비현실적 → 팀이 SLO 자체 무시.

다음: [lab-04-alertmanager-routing.md](./lab-04-alertmanager-routing.md)
