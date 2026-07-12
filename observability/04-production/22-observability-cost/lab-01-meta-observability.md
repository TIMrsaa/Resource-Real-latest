# Lab 01 — 관측의 관측: 자기 계측 대시보드·알림

> 관측 스택 자신을 관측하는 3층(볼륨·건강·비용 추정)을 구축합니다 — 파트 곳곳에서 만든 자기 메트릭들을 하나의 대시보드와 알림 세트로 종합하는 실습입니다.

## 0. 준비 — 통합 미니 스택

```bash
kind create cluster --name metaobs
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null
helm repo add fluent https://fluent.github.io/helm-charts 2>/dev/null
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace --set prometheus.prometheusSpec.retention=24h

# Fluent Bit (메트릭 서버 켜고, 목적지는 null — 볼륨 계측이 목적)
cat > /tmp/fb-meta.yaml <<'EOF'
config:
  service: |
    [SERVICE]
        Flush        1
        HTTP_Server  On
        HTTP_Port    2020
  inputs: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/*.log
        Tag               kube.*
        multiline.parser  cri
        DB                /var/log/flb_meta.db
  filters: |
    [FILTER]
        Name    kubernetes
        Match   kube.*
        Merge_Log On
  outputs: |
    [OUTPUT]
        Name    null
        Match   kube.*
serviceMonitor:
  enabled: true          # ★ Fluent Bit 자기 메트릭을 Prometheus로!
EOF
helm install fluent-bit fluent/fluent-bit -n monitoring -f /tmp/fb-meta.yaml
kubectl -n monitoring rollout status ds/fluent-bit --timeout=120s

# 볼륨을 만드는 앱 둘 (한 팀은 얌전, 한 팀은 시끄러움 — 귀속의 재료)
kubectl create namespace team-a; kubectl create namespace team-b
kubectl -n team-a create deployment quiet --image=busybox -- sh -c 'while true; do echo "{\"level\":\"info\",\"msg\":\"tick\"}"; sleep 5; done'
kubectl -n team-b create deployment noisy --image=busybox --replicas=2 -- sh -c 'while true; do echo "{\"level\":\"debug\",\"msg\":\"chatter chatter chatter\"}"; sleep 0.05; done'
sleep 120
```

## 1. 볼륨 층 — 누가 얼마나 만드나

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
sleep 3

# 로그 볼륨 (Fluent Bit 자기 메트릭 — input 레코드율)
curl -s 'localhost:9090/api/v1/query?query=rate(fluentbit_input_records_total[5m])' | grep -o '"value":\[[^]]*\]' | head -2
# noisy가 지배하는 수치

# 메트릭 시계열 총량과 범인 순위 (08 lab-02의 재사용)
curl -s 'localhost:9090/api/v1/query?query=prometheus_tsdb_head_series' | grep -o '"value":\[[^]]*\]'
curl -s 'localhost:9090/api/v1/query?query=topk(5,count%20by%20(__name__)({__name__=~".%2B"}))' | head -c 400
```

**귀속의 씨앗** — Fluent Bit 메트릭엔 네임스페이스 구분이 없지만, kubernetes 필터가 붙인 메타데이터로 저장소 쪽(Loki·CW)에서 네임스페이스별 볼륨을 잴 수 있습니다(13의 그룹별 IncomingBytes가 그 예). 여기서는 파이프라인 총량+타깃별 scrape_samples로 근사합니다:

```bash
# 타깃(팀)별 메트릭 기여
curl -s 'localhost:9090/api/v1/query?query=sum(scrape_samples_scraped)%20by%20(namespace)' | head -c 400
```

## 2. 건강 층 — 유실·적체의 상설 감시

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: observability-health
  namespace: monitoring
  labels: { release: monitoring }
spec:
  groups:
    - name: obs.health
      rules:
        - alert: LogPipelineDropping
          expr: rate(fluentbit_output_dropped_records_total[5m]) > 0
          for: 5m
          labels: { severity: page, team: platform }
          annotations: { summary: "로그 유실 발생 중 — 버퍼/목적지 점검 (06)" }
        - alert: LogPipelineRetrying
          expr: rate(fluentbit_output_retries_total[5m]) > 1
          for: 10m
          labels: { severity: ticket, team: platform }
          annotations: { summary: "로그 재시도 지속 — 목적지 불안 (계단 1단)" }
        - alert: MetricsSeriesSurge
          expr: |
            prometheus_tsdb_head_series
            > 1.5 * (prometheus_tsdb_head_series offset 1h)
          for: 10m
          labels: { severity: page, team: platform }
          annotations: { summary: "시계열 1시간 새 50% 급증 — 카디널리티 폭발 의심 (03)" }
        - alert: ObservabilityWatchdog     # ★ dead man's switch (14)
          expr: vector(1)
          labels: { severity: none, team: platform }
          annotations: { summary: "항상 발화 — 이 알림이 끊기면 알림 체계가 죽은 것" }
EOF
```

**설계 읽기** — 파트의 사고들이 알림이 됐습니다: 드롭(06의 조용한 유실), 재시도(07의 계단 1단), 시계열 급증(03의 폭발 — offset 비교로 "어제의 나"와 대조), 워치독(14의 교훈). **관측 플랫폼의 장애는 모든 장애를 가리므로 이 알림들의 심각도는 높게** 잡습니다.

## 3. 비용 추정 층 — 청구서 3주 전에

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: observability-cost
  namespace: monitoring
  labels: { release: monitoring }
spec:
  groups:
    - name: obs.cost
      interval: 60s
      rules:
        # 일일 로그 바이트 추정 (bytes/s × 86400)
        - record: cost:log_bytes:per_day
          expr: sum(rate(fluentbit_input_bytes_total[30m])) * 86400
        # 월 메트릭 샘플 추정 (14의 계산식을 rule로!)
        - record: cost:metric_samples:per_month
          expr: sum(rate(prometheus_tsdb_head_samples_appended_total[30m])) * 2592000
        # 단가를 곱한 추정 비용 (단가는 상수로 — 최신 요금표에서 갱신)
        - record: cost:log_usd:per_month_estimate
          expr: (sum(rate(fluentbit_input_bytes_total[30m])) * 86400 * 30 / 1e9) * 0.5
          # ↑ 예시 단가 $0.5/GB — 자기 계약 단가로 교체
EOF
sleep 90
curl -s 'localhost:9090/api/v1/query?query=cost:log_usd:per_month_estimate' | grep -o '"value":\[[^]]*\]'
# → "이대로면 월 $X" — 실시간 비용 추정 시계열!
```

**의미** — 청구서(월 1회·3주 후행)가 아니라 30분 창의 추세로 비용을 봅니다. 여기에 "어제 대비 3배" 알림을 걸면 13의 사고(debug 방치 8배)가 몇 시간 안에 잡힙니다.

## 4. 대시보드 조립 (09의 방법론을 자신에게)

```
"관측 플랫폼" 대시보드 구성 (09의 L1 형식):
  R열(볼륨): 로그 bytes/day 추이·시계열 총량·span 수집률
  E열(건강): 드롭·재시도·실패 (0이어야 할 것들)
  D열(비용): 월 추정 비용 게이지 + 어제 대비 변화율
  + 범인 표: top 메트릭·top 네임스페이스(볼륨 기여)
→ 플랫폼 팀의 L1 — 매주 월요일 보는 화면
```

## 5. 정리

```bash
kill %1 2>/dev/null || true
# 클러스터는 lab-02에서 계속
```

## 정리

- 자기 계측 3층 구축: 볼륨(범인 순위)·건강(드롭·급증·워치독)·비용(실시간 추정)
- 파트의 사고들이 알림 규칙이 됐습니다 — 06 유실·03 폭발·07 계단·14 워치독
- 비용 추정 rule = 청구서보다 3주 빠른 신호 (급증을 시간 단위로)
- 관측 플랫폼 대시보드 = 09의 방법론을 자신에게 (플랫폼 팀의 L1)
- **★ 통제의 전제는 가시성 — 관측이 자신을 관측하지 못하면 비용은 청구서로만 옵니다**
