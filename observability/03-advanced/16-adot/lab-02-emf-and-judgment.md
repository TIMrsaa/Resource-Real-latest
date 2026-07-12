# Lab 02 — awsemf 경로·수집 통합·판단 정리

> CW에 꼭 필요한 소수 지표를 EMF 경로로 보내는 분배를 추가하고, ADOT의 prometheus receiver로 "스크레이프 통합" 갈래를 확인한 뒤, ADOT vs 순정의 판단을 정리합니다.

## 0. 준비 (lab-01 이어서)

## 1. awsemf 분배 추가 — CW가 필요한 소수 지표

시나리오: CW 알람(13)과 통합해야 하는 지표 하나(주문 처리율)만 CW로도 보냅니다.

```bash
kubectl -n observability patch opentelemetrycollector adot --type merge -p '
spec:
  config:
    exporters:
      awsxray:
        region: '"$REGION"'
      prometheusremotewrite:
        endpoint: '"${AMP_ENDPOINT}"'api/v1/remote_write
        auth: { authenticator: sigv4auth }
      awsemf:
        region: '"$REGION"'
        namespace: Shop/Orders
        log_group_name: /adot/emf/shop
    service:
      pipelines:
        metrics:
          receivers: [otlp]
          processors: [memory_limiter, filter/cw, batch]
          exporters: [prometheusremotewrite, awsemf]
    processors:
      memory_limiter: { check_interval: 1s, limit_percentage: 75, spike_limit_percentage: 20 }
      k8sattributes: {}
      batch: {}
      filter/cw:
        metrics:
          include: { match_type: regexp, metric_names: ["http_server_duration.*"] }
'
# (개념 단순화를 위해 한 파이프라인에 필터를 걸었습니다 — 실전은 CW행 별도
#  파이프라인을 만들어 AMP행은 전체, CW행은 filter로 소수만 보내는 구성이 정석)
kubectl -n observability rollout status deploy/adot-collector --timeout=180s

# 트래픽 후 확인
kubectl -n shop run traffic2 --image=curlimages/curl --restart=Never -- sh -c '
  for i in $(seq 1 20); do curl -s http://app-a:8080/order >/dev/null; sleep 1; done'
sleep 120

# EMF 로그 그룹과 추출된 CW 메트릭 확인
aws logs describe-log-groups --region $REGION --log-group-name-prefix /adot/emf \
  --query 'logGroups[].logGroupName'
aws cloudwatch list-metrics --region $REGION --namespace Shop/Orders \
  --query 'Metrics[0:3].MetricName'
# http_server_duration... ← ★ 로그를 경유해 CW 메트릭이 생겼습니다 (EMF의 실체)
# retention 설정 잊지 말 것! (13)
aws logs put-retention-policy --region $REGION \
  --log-group-name /adot/emf/shop --retention-in-days 1
```

**분업 확인** — 이제 같은 메트릭이 AMP(주력 — 전체·고카디널리티·PromQL)와 CW(소수 — CW 알람·AWS 통합용)에 있습니다. 13의 분업("고카디널리티는 AMP, CW는 핵심 소수")이 filter 하나로 구현됐습니다 — 분배 설계가 곧 비용 설계입니다.

## 2. 스크레이프 통합 갈래 — prometheus receiver

```
개념 확인 (구성 스케치):
  receivers:
    prometheus:
      config:
        scrape_configs:        # Prometheus의 그 문법 그대로
          - job_name: kube-state-metrics
            kubernetes_sd_configs: [...]
  → ADOT가 /metrics 스크레이프까지 수행 → AMP로 remote_write

의미: "Prometheus 에이전트 모드(14)"의 대체 갈래 —
  OTLP(push) + 스크레이프(pull)를 한 수집기가
장단:
  + 수집기 하나로 통합 (운영 단순화 — 07·11의 통합 흐름의 종착)
  - ServiceMonitor CRD 생태(08의 셀프서비스)와의 연결은 별도 구성
    (target allocator가 SM을 읽는 구성도 있음 — 발전 중)
→ 판단: 이미 kube-prometheus-stack 체계(08)가 있으면 유지+remote_write(14),
  그린필드·수집기 최소화 지향이면 ADOT 통합 검토
```

## 3. 판단 정리 — ADOT vs 순정, 그리고 전체 그림

```
ADOT를 고르는 조직:
  EKS 중심, 백엔드가 AMP·X-Ray·CW — AWS 지원(이슈 때 물을 곳)과
  애드온 수명주기(업그레이드 관리)가 값

순정 OTel을 고르는 조직:
  contrib의 특수 컴포넌트 필요(다양한 exporter·processor),
  멀티클라우드 동일 구성, 최신 기능 추종

혼합: agent층 ADOT(애드온 편의) + gateway층 순정(tail 샘플링 등 특수)
설정 호환 → 갈아타기 부담 작음 — 가벼운 ADR로

[AWS 관측 스택 완성도 점검 — 13~16의 그림]
  수집: Fluent Bit(로그, 13) + ADOT(메트릭·트레이스, 16)
  저장: CW Logs(13)·AMP(14)·X-Ray(17에서 소비)
  화면: AMG(15) — 세 데이터소스
  남은 것: X-Ray 조사 동선(17), OpenSearch 선택지(18)
```

## 4. SIGNALS-MAP 갱신 (과제)

```
AWS 열 갱신:
  트레이스: OTel 계측(11 그대로) → ADOT → X-Ray  ✅(소비는 17)
  메트릭: OTLP → ADOT → AMP(주력) + awsemf → CW(핵심 소수)
  수집기: ADOT(애드온·IRSA 3정책) — 11 문법 그대로
```

## 5. 정리

```bash
bash cleanup.sh   # ADOT·IRSA·EMF 로그 그룹 정리 (AMP는 17에서 계속 쓰면 유지)
```

## 정리

- awsemf = 로그 경유 메트릭 — CW 필요 소수만 filter로 (13의 분업 구현, retention 잊지 말 것)
- 분배 설계 = 비용 설계: AMP(전체) + CW(소수)를 파이프라인 분기로
- prometheus receiver로 스크레이프 통합 갈래 — 기존 08 체계가 있으면 유지가 단순
- ADOT vs 순정: AWS 중심=ADOT(지원·애드온) / 특수·멀티클라우드=순정 — 설정 호환이라 결정 가벼움
- **★ 13~16으로 AWS 관측 스택의 뼈대 완성 — 17(X-Ray 동선)·18(로그 3파전)이 마무리**
