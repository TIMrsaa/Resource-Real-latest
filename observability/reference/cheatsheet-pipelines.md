# 파이프라인·쿼리 치트시트 (Fluent Bit · LogQL · Logs Insights · Collector)

## Fluent Bit 핵심 설정 (06·07)

```ini
[SERVICE]
    storage.path  /var/log/flb-storage/      # fs 버퍼 (프로덕션 표준)
    HTTP_Server   On                          # :2020 자기 메트릭 (22)

[INPUT]
    Name              tail
    Path              /var/log/containers/*.log
    Tag               kube.*                  # 경로가 tag에 (라우팅 키)
    multiline.parser  cri                     # ★ CRI 벗기기 + P/F 재조립 (02)
    DB                /var/log/flb.db         # 오프셋 영속 (재시작 대비)
    storage.type      filesystem

[FILTER]
    Name              kubernetes              # 메타데이터 부착
    Match             kube.*
    Merge_Log         On                      # ★ JSON 승격 (02 구조화의 보상)
    Use_Kubelet       On                      # 대규모 API 부하 분산

[FILTER]
    Name    grep                              # 수문 = 돈 (13)
    Match   kube.*
    Exclude log /healthz

[OUTPUT]
    Name                     forward           # (07: 2층) 또는 loki/cloudwatch_logs/opensearch
    Match                    kube.*
    Require_ack_response     True              # 유실 창 축소
    Retry_Limit              False             # fs가 받칠 때 무제한
    storage.total_limit_size 500M              # 디스크 한도 (필수!)
```

**진단**: `fluentbit_output_dropped_records_total`(유실!)·`retries_total`(목적지 불안)·input/output 격차(적체) — 알림 대상 (06·22).

## LogQL (12 — Loki)

```logql
{namespace="shop", app="payment"}              # 라벨로 좁힘 (인덱스)
  |= "timeout"                                 # 본문 grep
  | json                                       # 필드 추출 (02의 보상)
  | level="error"                              # 필드 필터
  | line_format "{{.event}} {{.user_id}}"

rate({app="payment"} |= "timeout" [5m])        # 로그의 메트릭화
sum by (level) (count_over_time({ns="shop"} | json [5m]))
```

**규율**: 라벨은 소수(namespace·app·level) — trace_id는 본문에(스트림 폭발, 03의 물리). 시간·라벨로 좁힌 뒤 grep이 설계에 맞는 습관.

## CloudWatch Logs Insights (13)

```
fields @timestamp, log_processed.event, log_processed.user_id
| filter log_processed.event = "pg_timeout"
| stats count() as failures by log_processed.user_id
| sort failures desc | limit 10

# audit 조사 (05·13)
filter @logStream like /audit/
| filter verb = "delete" and objectRef.resource = "deployments"
| fields user.username, objectRef.name, @timestamp
```

**규율**: 시간 범위 최소화(스캔 과금), 반복 질의는 메트릭 필터로 승격. retention 설정이 첫 행동(Never expire 방치 금지).

## OTel Collector (11·16)

```yaml
receivers:
  otlp: { protocols: { grpc: {}, http: {} } }
processors:
  memory_limiter:                              # ★ 항상 첫 번째 (자기 보호)
    check_interval: 1s
    limit_percentage: 75
    spike_limit_percentage: 20
  k8sattributes: {}                            # 메타 부착 (agent 층에서)
  tail_sampling:                               # ★ gateway에서만 (span 집결 필요)
    policies:
      - { name: errors, type: status_code, status_code: { status_codes: [ERROR] } }
      - { name: slow, type: latency, latency: { threshold_ms: 500 } }
      - { name: base, type: probabilistic, probabilistic: { sampling_percentage: 10 } }
  batch: {}
exporters:
  otlp/tempo: { endpoint: tempo:4317 }         # 백엔드 교체 = 이 줄 (11의 보상)
  awsxray: { region: ap-northeast-2 }          # ADOT (16·17)
  prometheusremotewrite:                       # AMP (14·16)
    endpoint: <AMP>api/v1/remote_write
    auth: { authenticator: sigv4auth }
service:
  pipelines:
    traces:  { receivers: [otlp], processors: [memory_limiter, k8sattributes, batch], exporters: [otlp/tempo] }
```

**배포 정석**: 앱→agent(DS, k8s 메타)→gateway(정책·tail)→백엔드 — 로그 2층(06→07)과 동형. 샘플링은 parentbased 통일, 결정 지점은 한 곳(16).

## 상관 배선 3종 (12)

```
로그→트레이스: Loki derived fields — 정규식 "trace_id":"(\w+)" → Tempo 링크
트레이스→로그: Tempo trace to logs — 라벨 매핑 (k8s.namespace.name→namespace!)
메트릭→트레이스: exemplar — Prometheus 기능 플래그 + 계측 + 패널 토글
전제: 로그의 trace_id 필드(02) · 라벨 일관성(06↔11) · W3C 전파(04)
```

## 유실의 물리 요약 (02·06·07·14 공통)

```
어디서든: 버퍼(fs·한도) × ack × 오프셋 영속 × 드롭 메트릭 알림
원칙: "유실 0"이 아니라 — 보이는 유실, 버티는 버퍼, 의도된 포기
등급: 감사·계약(SLO) 신호는 강한 보장, 소음은 수문에서 차단
```
