# Part 5 링크 모음

> 링크는 낡습니다 — 깨지면 프로젝트 공식 사이트에서 재검색.

## 원전·방법론

- Google SRE Book / SRE Workbook (SLO·멀티윈도우 번레이트·포스트모템 — 21·23의 원전): sre.google/books
- 12-factor logs: 12factor.net/logs (02)
- RED(Tom Wilkie)·USE(Brendan Gregg) 방법론 (09)
- Brendan Gregg 플레임그래프 자료 (20)
- Rob Ewaschuk "My Philosophy on Alerting" (10)
- PagerDuty Incident Response 공개 문서 (23 — IC 체계)

## 로그 파이프라인

- Fluent Bit: docs.fluentbit.io (tail·kubernetes filter·buffering·monitoring — 06)
- Fluentd: docs.fluentd.org (config·forward·buffer — 07)
- kubernetes-event-exporter: github.com/resmoio/kubernetes-event-exporter (05)
- Loki: grafana.com/docs/loki (라벨·LogQL — 12)
- OpenSearch: opensearch.org/docs (매핑·ISM·샤드 — 18)

## 메트릭

- Prometheus: prometheus.io/docs (노출 형식·relabel·알림 — 03·08·10)
- kube-prometheus-stack: github.com/prometheus-community/helm-charts (08)
- Prometheus Operator(CRD): prometheus-operator.dev (08)
- metrics-server: github.com/kubernetes-sigs/metrics-server (03)
- Alertmanager: prometheus.io/docs/alerting (10)
- Thanos: thanos.io / Mimir: grafana.com/docs/mimir (24)
- sloth·pyrra (SLO→rules 생성기 — 21)

## 트레이스·계측

- W3C Trace Context: w3.org/TR/trace-context (04)
- OpenTelemetry: opentelemetry.io/docs (Operator·Collector·언어별 — 11)
- Collector builder(ocb): opentelemetry.io/docs/collector/custom-collector (26)
- Tempo: grafana.com/docs/tempo (12)
- Grafana(대시보드·프로비저닝·데이터소스 상관): grafana.com/docs (09·12)

## AWS 관측 (13~18)

- CloudWatch 요금: aws.amazon.com/cloudwatch/pricing (★ 항상 최신 확인 — 13)
- Container Insights 애드온: docs.aws.amazon.com/AmazonCloudWatch (13)
- AMP: docs.aws.amazon.com/prometheus + 요금 (14)
- AMG: docs.aws.amazon.com/grafana + 요금(사용자당) (15)
- ADOT: aws-otel.github.io (16)
- X-Ray: docs.aws.amazon.com/xray (세그먼트·샘플링·필터 표현식 — 17)
- OpenSearch Service/Serverless: docs.aws.amazon.com/opensearch-service (18)
- awscurl (SigV4 쿼리 도구 — 14)

## 심층 (19~20)

- Cilium Hubble: docs.cilium.io (observability — 19)
- Pixie: px.dev / Grafana Beyla (eBPF 자동 관측 — 19)
- Parca: parca.dev / Pyroscope: grafana.com/docs/pyroscope (20)

## 카오스·게임데이 (23)

- Chaos Mesh: chaos-mesh.org / Litmus: litmuschaos.io

## 기여 (25~26)

- github.com/fluent · github.com/prometheus · github.com/open-telemetry · github.com/grafana
- OTel 커뮤니티(SIG 목록·캘린더): opentelemetry.io/community
- exporter 목록: prometheus.io/docs/instrumenting/exporters
- CLOTributor: clotributor.dev (cncf 50)
- CNCF Slack: slack.cncf.io

## 커리큘럼 내 연결

- cncf 11~14 (Prometheus·OTel·Jaeger·Fluentd의 내부 원리 — 이 파트의 이론 기반)
- cncf 22 (eBPF — 19의 기반) · cncf 45 (Thanos·Loki 자리매김 — 24)
- cncf 48 (비교 방법론 — 이 파트의 판단들) · cncf 49~50 (거버넌스·기여 — 25~26)
- eks 파트 (클러스터·IRSA·비용 가드레일 — 13~18의 실습 기반)
