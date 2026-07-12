# Lab 02 — Recording Rules + Alert Rules

> **🌱 Recording Rule 이 뭔가? 왜 쓰나?**
> **Recording Rule** = 자주 쓰는 비싼 PromQL 쿼리를 미리 평가해 새 메트릭으로 저장.
> ```
>   매 평가 주기마다:
>     PromQL 실행 → 결과를 새 시계열로 TSDB 저장
>   대시보드/알람:
>     비싼 쿼리 대신 사전 계산된 단순 메트릭 lookup → 빠름
> ```
>
> **언제 만드나?**
> - 같은 비싼 쿼리를 여러 대시보드 패널/알람이 사용
> - histogram_quantile 등 무거운 함수
> - 다중 클러스터 federation 시 중앙으로 보낼 요약 지표
>
> **Alert Rule** = expr 가 true 면 alert 발생. 같은 PrometheusRule CRD 안에 함께 정의.

## 1. Recording Rule 적용

```bash
kubectl apply -f manifests/recording-rules.yaml
kubectl get prometheusrule -n monitoring
```

> **🧠 PrometheusRule CRD 의 동작**
> Prometheus Operator 가 `PrometheusRule` 객체를 watch → 자동으로 Prometheus 의 rule config 에 merge → reload.
> = ConfigMap 직접 수정 불필요.
>
> **selector**: Prometheus.spec.ruleSelector 에 `release: kps` 같은 라벨 매칭 설정. 일치해야 로딩.
> (ServiceMonitor 와 같은 패턴)

## 2. Prometheus 가 rule 등록 확인

http://localhost:9090/rules — 그룹 목록에 `order-msa.recording`, `order-msa.alerts`.

> **🧠 /rules 페이지 읽는 법**
> 각 rule 마다:
> - **State**: `OK` (평가 성공) / `Err` (PromQL 에러)
> - **Last Evaluation**: 마지막 평가 시각
> - **Evaluation Time**: 평가 소요 시간 — **너무 길면 (>10s) 위험 신호**
> - **Health**: 그룹 단위 건강 상태
>
> 평가가 interval 보다 오래 걸리면 다음 평가 누락 → 알람 지연. 비싼 rule 발견 즉시 단순화.

## 3. recorded metric 직접 쿼리

원래 비싼 쿼리:
```promql
histogram_quantile(0.99,
  sum by (le, namespace, service) (
    rate(gin_request_duration_seconds_bucket[5m])
  )
)
```

이제 단순 metric 으로:
```promql
namespace:http_latency_p99:seconds
```

→ **Grafana 대시보드는 recorded metric 을 사용** 해야 빠르고 가벼움.

> **🧠 비용 절감 효과**
> 위 비싼 쿼리를 30개 대시보드 패널이 사용 + 5초마다 refresh:
> - **without recording**: 매 5초마다 30회 평가 = 6 평가/s × bucket × pod
> - **with recording**: 30s 마다 1회 평가 → 단순 lookup 30회
>
> CPU 사용량 50~100배 차이. Grafana 로딩 시간 5s → 200ms.

## 4. Naming convention (Brian Brazil)

```
level:metric:operation

level         — 어느 차원에서 (namespace / pod / instance)
metric        — 무엇 (http_rps / cpu_utilization / latency)
operation     — 무엇을 했나 (sum / ratio / p99)
```

좋은 예:
- `namespace:http_rps:sum`
- `pod:cpu_utilization:ratio`
- `instance:node_cpu:rate1m`

나쁜 예:
- `my_rps` (level 불명)
- `total_requests` (operation 불명)

> **🧠 왜 콜론 (`:`) 을 쓰나?**
> Prometheus 가 메트릭 이름에 `:` 허용 (앱이 노출하는 메트릭은 보통 `_` 사용).
> = recording rule 결과는 시각적으로 즉시 구분 가능 (`http_requests_total` vs `namespace:http_rps:sum`).
>
> 운영팀이 "이건 raw 데이터" / "이건 사전 계산" 한눈에 구분.

## 5. Alert rule 동작 확인

http://localhost:9090/alerts — 등록된 alert 들.

`HighErrorRate` 가 `Inactive` 면 정상 (에러율 5% 미만).

> **🧠 Alert 의 3가지 상태**
> - **Inactive**: expr 가 false (정상)
> - **Pending**: expr 가 true 가 됐고 `for:` 시간 카운트 중 (아직 통보 안 함)
> - **Firing**: `for:` 통과 → Alertmanager 로 통보
>
> Pending 단계가 핵심 — 일시적 spike 는 Pending 에서 끝나고 firing 안 됨.
> for: 5m 이면 "5분간 지속되어야 진짜 alert".

### 인위적으로 발생시키기

```bash
# order-service 의 새 요청에 의도적 에러 (예: 잘못된 JSON)
kubectl run -it --rm err-gen --image=alpine -n order -- sh -c "
  apk add -q curl &&
  for i in \$(seq 1 1000); do
    curl -sX POST http://order-service/orders -H 'Content-Type: application/json' -d 'INVALID' > /dev/null
  done"

# 5xx 가 안 나면 (앱이 400 만 응답해서) — 다른 부하 생성기 사용 또는 시뮬레이션
```

또는 메트릭 자체를 manual 로 push (Pushgateway 사용 예):
```bash
# Pushgateway 가 떠 있다면
echo "fake_5xx 1" | curl --data-binary @- http://pushgateway:9091/metrics/job/test
```

> **🧠 Pushgateway 의 용도와 함정**
> 일반 Prometheus = Pull. 하지만 **단명 (short-lived) 작업** (CronJob, batch) 은 Pull 안 됨 (이미 종료).
> → Pushgateway 가 Push 받아 보관, Prometheus 가 Pushgateway 를 Pull.
>
> **함정**:
> - Pushgateway 는 메트릭을 무제한 보관 (TTL 없음) → 옛 작업 메트릭 영구 누적
> - **장기 실행 서비스에 쓰면 안티패턴** (그건 일반 Pull /metrics 사용)
> - 단명 작업 전용 — 끝난 작업의 메트릭은 명시적으로 DELETE 해줘야

## 6. Alert 의 Pending → Firing → Resolved 라이프사이클

```
Pending  ─── 조건 만족 시작
   ↓
   for: 5m  유지
   ↓
Firing   ─── Alertmanager 로 통지
   ↓
   조건 해제 + resolve_timeout 후
   ↓
Resolved
```

`for: 5m` 의 의미: 5분 동안 expr 가 true 면 alert. 일시적 spike 무시.

> **🧠 `for:` 값 결정 가이드**
> | 메트릭 종류 | 권장 for: | 이유 |
> |------------|----------|------|
> | 노드 NotReady | 1~2m | 빠른 대응 필요 |
> | CPU 사용률 높음 | 5~10m | 일시 spike 허용 |
> | 디스크 가득 | 5m | 트렌드 확인 |
> | 에러율 폭증 | 2~5m | SLO 영향 큼 |
> | SSL 만료 임박 | 1h | 절대값 기반 |
>
> **너무 짧음** = noise (일시 spike 마다 알람), **너무 김** = 사고 늦게 발견.
> 황금 비율: `for: ≥ 평가 interval × 4`.

## 7. 자주 쓰는 alert 패턴

### 7.1 Multi-window
```yaml
expr: |
  (
    namespace:http_error_rate:ratio > 0.05
    and
    namespace:http_error_rate:ratio offset 1h > 0.05
  )
```
→ 1시간 전부터 지속된 문제만 alert (false positive 줄임).

> **🧠 `offset` 의 의미와 multi-window 의 가치**
> `metric offset 1h` = "1시간 전의 그 값".
>
> Multi-window 패턴: 짧은 윈도우 (현재 spike) AND 긴 윈도우 (지속성) 동시 검증.
> = "지금도 문제 + 1시간 전부터 문제" → 진짜 사고. 일시 spike 는 둘 다 만족 못 함.
>
> Google SRE 에서 권장하는 **multi-burn-rate alerting** 의 기초.

### 7.2 Burn-rate (SLO)
다음 모듈 23 에서 본격 다룸. 미리보기:
```yaml
- alert: ErrorBudgetBurning
  expr: |
    (
      sum(rate(http_requests_total{status=~"5.."}[1h])) / sum(rate(http_requests_total[1h])) > 0.05
      and
      sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) > 0.05
    )
  for: 2m
```

> **🧠 burn-rate 의 직관**
> SLO=99.9% 면 error budget = 0.1%. 한 달 약 43분 다운 허용.
> "burn rate 14.4" = "이 속도면 budget 을 1시간에 다 태움".
>
> 단순 임계값 (5% 에러) 보다 **얼마나 빨리 budget 소진되는지** 가 운영적으로 더 중요.
> 짧은 윈도우 + 긴 윈도우 동시 → fast burn (즉시 page) vs slow burn (티켓) 구분.

## 8. recording rule 의 비용 vs 이점

### 비용
- 추가 시계열 (record 마다 1개 — 차원에 따라 N개)
- 평가 주기마다 쿼리 실행 (CPU)

### 이점
- 대시보드 / alert 가 단순 lookup → 빠름
- 같은 비싼 쿼리를 30+ 패널이 쓴다면 큰 절감

→ 자주 쓰는 비싼 쿼리만 recording 권장.

> **🧠 recording rule 이 오히려 손해인 경우**
> - 한 패널만 쓰는 쿼리 — 직접 쿼리가 같은 비용
> - 결과 cardinality 가 매우 큼 (`by (pod)` 인데 Pod 가 1만 개) — recorded series 도 1만 개 → cardinality 폭발
> - 평가 비용이 lookup 보다 큼 (드물게)
>
> **체크리스트**:
> - [ ] 2개 이상 패널/알람이 사용?
> - [ ] 결과 cardinality < 1000?
> - [ ] 평가 시간 < interval / 4?
> 셋 다 yes 면 recording rule 가치 있음.

## 학습 확인

1. recording rule 의 평가 주기 (`interval`) 가 너무 짧으면 어떤 부작용?
2. alert 의 `for` 와 recording rule 의 `interval` 의 관계는?
3. recording rule 의 `record` 이름이 잘못됐을 때 검증 방법?

> **힌트**:
> 1. CPU 부담 증가 + 시계열 쓰기 폭증. 평가 시간이 interval 넘으면 경고. 보통 30s ~ 1m.
> 2. for 는 보통 interval 의 2~3배 이상 권장 (한 평가 누락 허용). interval=30s 면 for >= 1m.
> 3. promtool check rules <file>. 또는 적용 후 /rules 페이지에서 State 확인. 잘못된 이름은 PromQL syntax error 또는 결과 누락.

다음: [quiz.md](./quiz.md)
