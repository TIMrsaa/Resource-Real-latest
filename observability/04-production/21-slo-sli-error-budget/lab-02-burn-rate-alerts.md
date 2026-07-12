# Lab 02 — 멀티윈도우 번레이트 알림: 구현과 검증

> 10의 알림 규율의 정점 — "얼마나 급하게 버짓을 태우나"로 울리는 멀티윈도우 번레이트 알림을 구현하고, 세 시나리오(급성 장애·순간 스파이크·느린 누수)로 설계가 의도대로 동작하는지 검증합니다.

## 0. 준비 (lab-01 이어서 — SLI rules 가동 중, SLO=98% → 허용 실패율 0.02)

## 1. 번레이트 알림 규칙

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: payment-burnrate
  namespace: shop
  labels: { release: monitoring }
spec:
  groups:
    - name: slo.burnrate
      rules:
        # PAGE: 빠른 소진 — 1h 창 번레이트 14.4× AND 5m 창도 (현재진행 확인)
        - alert: PaymentBudgetFastBurn
          expr: |
            slo:payment_error_ratio:rate1h  > 14.4 * 0.02
            and
            slo:payment_error_ratio:rate5m  > 14.4 * 0.02
          labels: { severity: page, team: commerce }
          annotations:
            summary: "버짓 급속 소진 — 이 속도면 30일 버짓이 ~2일에 증발 (1h 번레이트 {{ $value }})"
            dashboard: "http://grafana/d/slo-payment"
            runbook: "https://runbooks.example/slo-fast-burn"
        # TICKET: 느린 누수 — 6h 창 3× AND 30m 창
        - alert: PaymentBudgetSlowBurn
          expr: |
            slo:payment_error_ratio:rate6h  > 3 * 0.02
            and
            slo:payment_error_ratio:rate30m > 3 * 0.02
          labels: { severity: ticket, team: commerce }
          annotations:
            summary: "버짓 느린 누수 — 방치 시 기간 내 SLO 위반 (6h 번레이트 {{ $value }})"
EOF
sleep 60
```

(실습 SLO 98%는 허용 실패율이 0.02라, 14.4× 임계는 실패율 28.8% — 검증이 극적이도록 의도된 수치입니다. 실전 99.9%면 임계는 1.44%.)

## 2. 시나리오 ① — 급성 장애 (page가 울려야)

```bash
# baseline(2% 에러)에 더해 대량 에러 주입 — 실패율 ~50%
kubectl -n shop run incident --image=curlimages/curl --restart=Never -- sh -c '
  while true; do curl -s http://payment:8080/err >/dev/null; sleep 0.05; done'

kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
sleep 3
# 5m 창은 곧 반응, 1h 창은 서서히 상승 — 두 창이 모두 넘으면 발화
watch -n 30 'curl -s "localhost:9090/api/v1/query?query=slo:payment_error_ratio:rate5m" | grep -o "\"value\":\[[^]]*\]"'
# rate5m이 0.5 근처로 → 잠시 후 rate1h도 0.288 초과 → FastBurn firing

curl -s localhost:9090/api/v1/alerts | grep -A3 FastBurn | grep state
# "state":"firing"   ← 급성 장애를 page가 잡았습니다
```

## 3. 시나리오 ② — 순간 스파이크 (울리지 말아야!)

```bash
kubectl -n shop delete pod incident --force --grace-period=0
sleep 600   # 창들이 회복될 때까지

# 30초짜리 에러 버스트 후 정상 복귀
kubectl -n shop run spike --image=curlimages/curl --restart=Never -- sh -c '
  for i in $(seq 1 300); do curl -s http://payment:8080/err >/dev/null; sleep 0.1; done'
sleep 120

curl -s localhost:9090/api/v1/alerts | grep -c FastBurn || echo "0"
# 0 (또는 pending 없이 소멸)
# 이유: 5m 창은 순간 넘었어도 1h 창이 임계 미달 — AND가 소음을 걸렀습니다
#       (10의 for보다 정교한 형태 — "이미 지나간 스파이크"에도 강함)
```

**검증 포인트** — 30초 버스트는 사용자 영향이 잠깐이고 버짓 소모도 작습니다 — 깨울 일이 아닙니다(10의 3심사). 단순 임계 알림이었다면 울렸을 상황을 멀티윈도우가 걸렀습니다.

## 4. 시나리오 ③ — 느린 누수 (ticket이 잡아야)

```bash
# baseline보다 살짝 높은 지속 에러 (~8% — page 임계 미달, 방치 시 SLO 위반)
kubectl -n shop run leak --image=curlimages/curl --restart=Never -- sh -c '
  while true; do
    for i in $(seq 1 11); do curl -s http://payment:8080/ >/dev/null; done;
    curl -s http://payment:8080/err >/dev/null;
    sleep 0.3;
  done'
# 6h 창이 3×0.02=0.06을 넘기까지 시간이 걸립니다 (실습에선 30m~ 관찰)
# → SlowBurn(ticket)이 잡습니다 — 단순 임계 "에러율>10%"였다면 영원히 침묵!
```

**설계의 완성 확인** — 세 시나리오가 세 결과: 급성=page(즉시), 스파이크=침묵(소음 억제), 누수=ticket(방치 방지). "버짓 관점의 심각도"가 알림의 언어가 됐습니다 — 10의 규율(증상·행동 가능·긴급성)이 수학적 형태를 얻은 것입니다.

## 5. 조직 계약의 코드화 (개념)

```
버짓 정책의 자동화 접점:
  budget_used_ratio > 0.5  → 배포 파이프라인에 경고 라벨 (cicd 연계)
  budget_used_ratio > 1.0  → 릴리즈 게이트 차단 (cncf 16의 롤아웃 분석·
                             cicd의 게이트와 결합 — "브레이크의 코드화")
  단, 자동 차단은 조직 합의가 먼저 — 코드는 계약의 집행일 뿐 (guide)

SLO 리뷰 루프(분기): 실적 vs 목표 vs 사용자 불만 대조 → 재협상
```

## 6. SIGNALS-MAP 갱신 (과제)

```
알림 줄 진화:
  체계: 3심사(10) + SLO 번레이트(멀티윈도우) — page 2규칙·ticket 2규칙
  기반: slo:* recording rules (창 계층)
  계약: 버짓 정책(50%/100% 발동선) — 문서 링크
```

## 7. 정리

```bash
kill %1 2>/dev/null || true
kind delete cluster --name slo
```

## 정리

- 번레이트 알림 = 긴 창(지속)+짧은 창(현재진행)의 AND — recording rules 위에
- 3중 검증: 급성=page / 스파이크=침묵 / 누수=ticket — 단순 임계가 못 하는 세 가지
- 실전 배율 관례: 14.4×(1h/5m)=page, 6×(6h/30m)=page, 1~3×(1~3d)=ticket
- 버짓 정책의 자동화(릴리즈 게이트)는 조직 합의의 집행 — 합의가 먼저
- **★ 알림의 완성형: "에러가 있다"가 아니라 "약속(SLO)을 지킬 수 없는 속도다"로 울립니다**
