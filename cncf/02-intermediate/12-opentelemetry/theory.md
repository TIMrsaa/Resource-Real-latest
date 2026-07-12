# 이론 — 데이터 모델, 컨텍스트 전파, 시맨틱 컨벤션, Collector, 샘플링

> **🌱 17세 눈높이 비유: 택배 송장**
> - **trace_id** = 주문 번호 — 물류센터·배송기사·편의점을 거쳐도 같은 번호
> - **span** = 각 구간의 처리 기록 — "물류센터 도착 14:02, 출발 14:31" (시작·끝·태그)
> - **부모 span_id** = "직전 어디서 왔는지" — 이것들이 이어져 여정(트레이스)이 됩니다
> - **컨텍스트 전파** = 송장을 상자에 **붙여서** 넘기는 것 — 안 붙이고 넘기면 다음 센터는 새 주문으로 오해(트레이스 조각남)
> - **traceparent 헤더** = 송장 규격(W3C 표준) — 어느 회사 트럭이든 읽을 수 있게
> - **시맨틱 컨벤션** = 송장의 항목 이름 규칙 — 어떤 회사는 "수취인", 어떤 회사는 "받는분"이면 통합 조회가 안 됩니다
> - **Collector** = 집하장 — 모든 송장을 받아 분류·가공해 각 보관소로. 집하장을 바꿔도 트럭(앱)은 그대로
> - **tail 샘플링** = "배송이 끝난 뒤" 판단 — 사고 난 건은 전부 보관, 정상 건은 1%만

---

## 1. 데이터 모델 — 세 신호와 그 접착제

```
Trace = span들의 트리
  span: { trace_id, span_id, parent_span_id, name, start, end, attributes[], events[], status }
  ★ trace_id는 여정 전체에서 동일, span_id는 구간마다 새로 생성

Metric = 계측값 (counter/gauge/histogram) + exemplar(→ trace_id 링크!)
Log   = 구조화 레코드 + trace_id/span_id 필드

★ 접착제 = trace_id
  메트릭에서 이상을 보고(exemplar로) 트레이스로 점프 → 그 trace_id로 로그 조회
  06의 사고 사례가 실패한 지점: 세 신호가 서로를 가리키지 못했습니다
```

Resource(어느 서비스·Pod·리전인지)는 세 신호 공통으로 붙는 메타데이터 — `service.name`이 없으면 아무것도 시작되지 않습니다.

## 2. 컨텍스트 전파 — 트레이스의 심장

### W3C Trace Context 표준

```
traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
             ^^ ^-------- trace_id (16B) -------^ ^- span_id -^ ^^
             버전                                   (부모)       플래그(01=sampled)

tracestate:  벤더별 추가 상태 (선택)
```

### 전파의 실제 흐름

```
[서비스 A]                                   [서비스 B]
현재 컨텍스트(trace_id, span_id)
  │ inject(propagator) → HTTP 헤더에 traceparent 삽입
  └──────────── HTTP 요청 ────────────────▶ extract(propagator) → 컨텍스트 복원
                                            새 span 생성 (parent = A의 span_id)
```

- **자동 계측(auto-instrumentation)**이 하는 일의 대부분이 이 inject/extract입니다 — 표준 HTTP 클라이언트·서버 라이브러리를 패치
- **끊기는 지점**:
  ```
  ① 비동기 경계: 큐(Kafka/SQS)에 메시지를 넣을 때 헤더에 컨텍스트를 안 실음
  ② 스레드/코루틴 경계: 컨텍스트가 thread-local이라 워커 스레드로 안 넘어감
  ③ 수동 HTTP 클라이언트: 계측 안 된 클라이언트로 직접 호출
  ④ 계측 안 된 서비스: 중간에 한 서비스가 헤더를 버리면 이후가 새 트레이스
  ```
- 진단: 조각난 트레이스(루트가 여러 개), "이 서비스만 트레이스에 안 보임"

## 3. 시맨틱 컨벤션 — 표준의 진짜 가치

```
컨벤션 없이:  service-a는 http.method, service-b는 httpMethod, service-c는 method
             → "5xx 비율" 대시보드를 서비스마다 다시 만들어야 함

컨벤션 있음:  전부 http.request.method / http.response.status_code / server.address
             → 대시보드·알람·SLO가 이식 가능. 새 서비스는 계측만 하면 화면이 이미 있습니다
```

- OTel의 시맨틱 컨벤션은 안정화 과정에서 이름이 바뀌기도 했습니다(`http.method` → `http.request.method`) — 마이그레이션 시 두 이름을 함께 받는 기간 필요
- Resource 컨벤션: `service.name`(필수), `service.version`, `deployment.environment`, `k8s.pod.name`(Collector가 자동 부착 가능 — §4)
- **커스텀 속성은 컨벤션을 침범하지 않는 네임스페이스로**(`myco.order.tier`)

## 4. Collector — 관측의 게이트웨이

```yaml
receivers:                     # 받습니다
  otlp: { protocols: { grpc: {}, http: {} } }
  prometheus: { config: {...} }     # 스크레이프도 가능(11과 합류)
  filelog: {...}
processors:                    # 가공합니다 (순서가 의미 있습니다!)
  memory_limiter: {}           # ★ 항상 첫 번째 (OOM 방어)
  k8sattributes: {}            # Pod 메타데이터 자동 부착
  resource: {...}              # 속성 추가·수정
  tail_sampling: {...}         # §5
  batch: {}                    # ★ 항상 마지막 (전송 효율)
exporters:                     # 내보냅니다
  otlp/jaeger: { endpoint: jaeger:4317 }
  prometheusremotewrite: {...}
  debug: {}
service:
  pipelines:
    traces:  { receivers: [otlp], processors: [memory_limiter, k8sattributes, tail_sampling, batch], exporters: [otlp/jaeger] }
    metrics: { receivers: [otlp, prometheus], processors: [memory_limiter, batch], exporters: [prometheusremotewrite] }
```

### 배포 토폴로지

| 형태 | 구조 | 자리 |
|---|---|---|
| **Agent** (DaemonSet) | 노드마다 하나 — 앱이 localhost로 전송 | 낮은 지연, k8s 메타 부착, 노드 리소스 |
| **Gateway** (Deployment) | 중앙 풀 — agent가 전달 | 집계·tail 샘플링·중앙 정책 |
| Sidecar | Pod마다 | 강한 격리, 비용 큼 |
| 없음 (SDK→백엔드 직결) | — | 소규모·PoC. 백엔드 교체 시 재배포 필요 |

실무 표준: **agent(DaemonSet) → gateway(Deployment) → 백엔드**. agent가 k8sattributes로 Pod 메타를 붙이고, gateway에서 tail 샘플링·라우팅.

### 배포 도구

```
OpenTelemetry Operator: Collector CR + 자동 계측 주입(Instrumentation CR)
  → 앱 코드 수정 없이 사이드카/init으로 언어별 에이전트 주입 (Java/Node/Python/.NET)
```

## 5. 샘플링 — 비용과 정보의 저울

| 전략 | 언제 결정 | 장점 | 한계 |
|---|---|---|---|
| **Head** (SDK) | 트레이스 시작 시 | 쌉니다(안 보낼 것을 안 만듦) | 결과를 모르고 결정 — 에러도 버려짐 |
| **Tail** (Collector) | 트레이스 완료 후 | **에러·느린 것만 남김** | 모든 span을 일단 받아야(비용), 메모리·시간 창 |
| Probabilistic | 확률 | 단순 | 위와 동일 |

```yaml
# tail_sampling 예시: 에러는 전부, 느린 것은 전부, 나머지는 1%
processors:
  tail_sampling:
    decision_wait: 10s          # 트레이스 완료를 기다리는 시간
    policies:
      - { name: errors, type: status_code, status_code: { status_codes: [ERROR] } }
      - { name: slow, type: latency, latency: { threshold_ms: 500 } }
      - { name: rest, type: probabilistic, probabilistic: { sampling_percentage: 1 } }
```

**tail 샘플링의 제약**: 한 트레이스의 모든 span이 **같은 Collector 인스턴스**에 모여야 판단이 가능합니다.

```
해법: gateway 앞에 loadbalancing exporter — trace_id로 해시해 같은 gateway로 라우팅
  agent → (loadbalancing exporter, routing_key: traceID) → gateway 풀 → 백엔드
★ 이 제약이 Collector 토폴로지 설계를 지배합니다
```

## 6. OTel이 하지 않는 것 (다시 못 박기)

```
저장하지 않습니다  (TSDB·트레이스 백엔드·로그 저장소 없음)
질의하지 않습니다  (쿼리 언어 없음)
그리지 않습니다    (대시보드 없음)
알람 없습니다
→ 백엔드: Jaeger/Tempo(트레이스), Prometheus/Mimir(메트릭), Loki/ES(로그)
→ OTel의 성공 지표는 "우리가 백엔드를 바꿀 때 앱을 안 건드렸는가"
```

## 7. 소스/도구에서 확인하기

- 명세: https://opentelemetry.io/docs/specs/otel/ (trace/metrics/logs 데이터 모델)
- 시맨틱 컨벤션: https://opentelemetry.io/docs/specs/semconv/
- W3C Trace Context: https://www.w3.org/TR/trace-context/
- Collector: https://opentelemetry.io/docs/collector/ — configuration, tail sampling
- Operator: https://github.com/open-telemetry/opentelemetry-operator

## 요약 카드

| 질문 | 답 |
|------|----|
| OTel의 본질 가치? | 계측의 벤더 독립 — 백엔드 교체가 exporter 한 줄(CSI·OCI와 같은 해방) |
| 트레이스의 심장? | 컨텍스트 전파 — W3C traceparent를 inject/extract |
| 전파 끊김 4대 원인? | 비동기 큐, 스레드 경계, 수동 HTTP 클라이언트, 미계측 서비스 |
| 시맨틱 컨벤션? | 같은 것을 같은 이름으로 → 대시보드·알람·SLO의 이식성 |
| Collector 파이프라인? | receivers → processors(memory_limiter 처음, batch 마지막) → exporters |
| 표준 토폴로지? | agent(DaemonSet, k8s 메타) → gateway(tail 샘플링) → 백엔드 |
| head vs tail 샘플링? | 싸지만 에러도 버림 vs 에러·느린 것만 남김(단, 같은 Collector에 모여야) |
| tail의 제약 해법? | loadbalancing exporter (routing_key: traceID) |
