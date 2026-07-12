# Lab 02 — relabeling 수문과 recording rules

> 03의 사고(라벨 폭발)를 수집 시점에 막는 metricRelabelings를 실습하고, 비싼 쿼리를 recording rule로 사전 계산해 대시보드·알림의 기반을 만듭니다.

## 0. 준비 (lab-01 이어서)

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
sleep 3
```

## 1. 현재 시계열 규모 파악 (통제의 기준선)

```bash
# 전체 활성 시계열 수 (TSDB head — cncf 11)
curl -s 'localhost:9090/api/v1/query?query=prometheus_tsdb_head_series' | grep -o '"value":\[[^]]*\]'
# 예: 45000 — kind 소규모에서도 수만!

# 어떤 메트릭이 가장 뚱뚱한가 (카디널리티 상위)
curl -s 'localhost:9090/api/v1/query?query=topk(5,count%20by%20(__name__)({__name__=~".%2B"}))' | head -c 600
# 대개 histogram bucket류(apiserver_request_duration_...)·etcd류가 상위
```

**관찰** — 아무 앱도 없는 클러스터가 이미 수만 시계열입니다. 대부분 컨트롤 플레인의 상세 메트릭 — 쓰지 않는다면 수문의 후보입니다.

## 2. metricRelabelings — 수문 설치

payment 앱의 Go 런타임 메트릭(go_*)을 저장 전에 버려 보자:

```bash
# 먼저 현재 go_* 시계열 확인
curl -s 'localhost:9090/api/v1/query?query=count({__name__=~"go_.*",namespace="shop"})' | grep -o '"value":\[[^]]*\]'
# 예: 70+ (인스턴스 2개 × go 메트릭 30여 개)

# ServiceMonitor에 수문 추가
kubectl -n shop patch servicemonitor payment --type merge -p '
spec:
  endpoints:
    - port: metrics
      interval: 15s
      metricRelabelings:
        - sourceLabels: [__name__]
          regex: "go_.*|promhttp_.*"     # 런타임·핸들러 메트릭 폐기
          action: drop
        - regex: "pod_template_hash"      # 무의미 고카디널리티 라벨 제거
          action: labeldrop
'
sleep 60
curl -s 'localhost:9090/api/v1/query?query=count({__name__=~"go_.*",namespace="shop"})' | grep -o '"value":\[[^]]*\]'
# 0 또는 감소 — ★ 새로 들어오는 것이 차단됨 (기존 것은 보존 기간까지 잔존)
```

**핵심** — drop은 **TSDB에 들어가기 전**에 작동합니다(03 사고의 예방선). 사후 삭제(admin API)는 응급처치일 뿐 — 수문이 정석입니다. 무엇을 버릴지의 기준: "이 메트릭으로 답할 질문이 있는가"(01) — 없으면 후보, 애매하면 보류(과잉 drop은 06 함정 5의 메트릭판).

## 3. sample_limit — 폭발의 안전벨트

```bash
# 타깃당 샘플 상한: 폭발한 타깃의 스크레이프를 통째로 실패시킴 (전체 보호)
kubectl -n shop patch servicemonitor payment --type merge -p '
spec:
  sampleLimit: 1000
'
# 정상(수백 샘플)에선 영향 없음. 만약 어떤 배포가 라벨 폭발을 내면
# → 그 타깃만 scrape 실패(up=0) → 알림 → 전체 TSDB는 보호
# 03의 사고(테넌트 라벨 폭발)에서 폭발 반경을 자르는 안전벨트
```

## 4. recording rules — 사전 계산

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: payment-slis
  namespace: shop
  labels: { release: monitoring }     # ruleSelector 매칭 (역시 사슬!)
spec:
  groups:
    - name: payment.sli
      interval: 30s
      rules:
        - record: service:http_requests:rate5m
          expr: sum by (namespace) (rate(http_requests_total[5m]))
        - record: service:http_error_ratio:rate5m
          expr: |
            sum by (namespace) (rate(http_requests_total{code=~"5.."}[5m]))
            /
            sum by (namespace) (rate(http_requests_total[5m]))
EOF

# 트래픽 재생성 (에러 포함 — /err 경로)
kubectl -n shop run gen2 --image=curlimages/curl --restart=Never -- \
  sh -c 'for i in $(seq 1 200); do curl -s http://payment:8080/ >/dev/null; curl -s http://payment:8080/err >/dev/null; sleep 0.1; done'
sleep 90

# 사전 계산된 시계열을 조회 (가볍고, 정의가 하나)
curl -s 'localhost:9090/api/v1/query?query=service:http_error_ratio:rate5m' | head -c 400
# {"metric":{"__name__":"service:http_error_ratio:rate5m","namespace":"shop"},"value":[...,"0.5"]}
# → 에러율 50% (/와 /err 반반) — 이 하나의 시계열을 대시보드·알림이 공유
```

**명명 관례 확인** — `level:metric:operations` (service:http_error_ratio:rate5m): 읽는 사람이 "무엇을 어떻게 집계했나"를 이름에서 압니다. 팀 공통 관례가 09·10·21의 어휘가 됩니다.

## 5. rule의 비용 자각

```bash
# rule도 시계열을 만듭니다 — rule 평가 상태 확인
curl -s localhost:9090/api/v1/rules | grep -o '"name":"[^"]*"' | head
# 기본 스택의 rule들 + 방금 만든 것
# 수백 개 rule × 라벨 조합 = 그것대로 시계열 (소비되는 것만 만들 것)
```

## 6. SIGNALS-MAP 갱신 (과제)

```
메트릭 줄 갱신:
  수집: Prometheus(Operator·ServiceMonitor 셀프서비스)
  수문: metricRelabelings(go_* drop)·sampleLimit
  보존: 24h(실습) — 장기는 14(AMP)·24(Thanos/Mimir)에서
  사전계산: service:* recording rules
  상태: ✅ (로컬 스택)
```

## 7. 정리

```bash
kill %1 2>/dev/null || true
kind delete cluster --name prom
```

## 정리

- 기준선: 빈 클러스터도 수만 시계열 — topk로 뚱뚱한 메트릭 파악이 통제의 시작
- metricRelabelings drop/labeldrop = **저장 전 수문** (사후 삭제는 응급처치)
- sampleLimit = 안전벨트: 폭발 타깃만 실패시켜 전체 TSDB 보호 (03 사고의 반경 통제)
- recording rule = 계산 1회·소비 N회 + **정의의 단일화** (명명 관례 level:metric:op)
- **★ 수집 체계의 완성 = 등록(SM) + 수문(relabel) + 안전벨트(limit) + 사전 계산(rule)**
