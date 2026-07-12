# 이론 — 계측 스펙트럼, Operator 주입, Collector 파이프라인, 배포 3패턴, 샘플링 배치

> **🌱 17세 눈높이 비유: 학교 행사 촬영단**
> - **수동 계측(직접 셀카)** = 각자 원하는 순간을 직접 찍음 — 정확하지만 모두가 카메라를 배워야
> - **자동 계측(행사장 자동 카메라)** = 입구·출구·무대(HTTP·DB 경계)에 설치된 카메라가 알아서 — 지나가기만 하면 찍힘
> - **Operator 주입(방송반이 카메라 설치)** = 각 반은 신청서(어노테이션)만 내면 방송반이 교실에 카메라를 달아줌 — 반 학생들은 아무것도 안 배워도 됨
> - **Collector(편집실)** = 모든 카메라가 영상을 편집실로 — 편집실이 자르고(샘플링) 정리해 방송국(백엔드)으로. 방송국을 바꿔도 카메라는 그대로
> - **agent→gateway** = 층마다 간이 편집대(agent) + 중앙 편집실(gateway) — 로그 수거(06→07)와 같은 구조
> - **핵심** = 촬영(계측)의 마찰을 줄이는 것이 보급의 열쇠 — 04의 조직 문제를 기술로 완화

---

## 1. 계측 스펙트럼

```
[제로 코드] ← 마찰 적음                          마찰 큼 → [풀 수동]
  Operator 주입     라이브러리 자동 계측      SDK 수동 span
  (어노테이션)       (앱에 패키지 추가)        (코드 작성)

자동이 커버: HTTP in/out, DB, gRPC, 메시징(전파 포함!) — 경계의 span
수동이 필요: 내부 단계 span, 커스텀 속성(business context), 특수 프로토콜

시맨틱 컨벤션 (cncf 12): 자동 계측이 표준 속성(http.route, db.system...)을
  보장 — 도구·백엔드가 이해하는 공통 어휘. 수동 속성도 컨벤션 따를 것

언어 현실:
  Java: -javaagent 런타임 주입 (가장 강력)
  Python: 부트스트랩 래핑 (강력)
  Node: require 훅 (강력)
  Go: 컴파일 언어 — 주입 불가, 라이브러리 통합(otelhttp 등)로 (수정 필요)
  → "제로 코드"의 가능 범위가 언어마다 다름을 알고 계획
```

## 2. OTel Operator — 주입의 실체

```
구성:
  OpenTelemetry Operator (helm) — 웹훅 + CRD 컨트롤러
  Instrumentation CRD — "무엇을 어떻게 주입할지"의 정의
  OpenTelemetryCollector CRD — Collector 배포도 CRD로

Instrumentation 예:
  apiVersion: opentelemetry.io/v1alpha1
  kind: Instrumentation
  metadata: { name: default }
  spec:
    exporter: { endpoint: http://collector:4317 }   # 어디로 보낼지
    propagators: [tracecontext, baggage]            # ★ W3C (04!)
    sampler: { type: parentbased_traceidratio, argument: "0.25" }
    java: { image: ...autoinstrumentation-java:... }
    python: { ... }

Pod 어노테이션:
  instrumentation.opentelemetry.io/inject-java: "true"
  → admission webhook이 Pod spec을 변형:
    init container(에이전트 복사) + env(JAVA_TOOL_OPTIONS, OTEL_*)
  → 앱 프로세스가 뜰 때 에이전트가 클래스를 계측

주입 실패의 단골: 웹훅이 안 봄(네임스페이스 라벨·타이밍),
  어노테이션 위치(Pod template이어야 — Deployment 메타데이터 아님!),
  Go 앱에 inject-java (언어 불일치)
```

## 3. Collector 파이프라인 — 신호 3종의 단일 문법

```yaml
receivers:                 # 어떻게 받나
  otlp:
    protocols: { grpc: {}, http: {} }
processors:                # 무엇을 하나 (순서 있음)
  memory_limiter: {...}    # ★ 첫 번째로 — 자기 보호 (06의 Mem_Buf_Limit 사상)
  k8sattributes: {}        # k8s 메타데이터 부착 (06의 kubernetes 필터와 동일 사상)
  batch: {}                # 배치 — 효율 (거의 항상)
exporters:                 # 어디로 보내나
  otlp/tempo: { endpoint: tempo:4317 }
  prometheusremotewrite: { endpoint: ... }    # 메트릭이면
  loki: { endpoint: ... }                     # 로그면
service:
  pipelines:
    traces:  { receivers: [otlp], processors: [memory_limiter, k8sattributes, batch], exporters: [otlp/tempo] }
    metrics: { receivers: [otlp], processors: [...], exporters: [prometheusremotewrite] }
    logs:    { receivers: [otlp], processors: [...], exporters: [loki] }

★ 06과의 대응: receiver=INPUT, processor=FILTER, exporter=OUTPUT
  파이프라인 사상은 하나 — 도구가 다를 뿐
★ 신호 3종이 한 설정에: "Collector로 통일" 흐름의 근거 (07 5절)
```

## 4. 배포 3패턴

```
sidecar (Pod마다):
  + 완전 격리(테넌트별), 앱과 생명주기 동일
  - Pod 수만큼 리소스 — 대규모에 무거움 (02의 사이드카 논의와 동일)
  → 특수(강한 격리 요구)에 한정

DaemonSet agent (노드마다):
  + 앱은 localhost(노드 IP)로 — 네트워크 홉 최소
  + k8sattributes에 유리 (로컬 kubelet)
  + 노드 수만큼 자동 확장 (06의 DaemonSet과 동일한 이유)
  → 수집 층의 표준

gateway (중앙 Deployment):
  + 백엔드 인증·연결 집중 (07의 애그리게이터와 동형)
  + ★ tail 샘플링의 자리 — 같은 trace의 span이 한곳에 모여야 (아래)
  + 무거운 가공·멀티 백엔드 라우팅
  - 새 운영점 (07의 교훈 그대로 — HA·버퍼·역류)

실전 조합: 앱 → agent(DS) → gateway → 백엔드들
  = 로그의 Bit→Fluentd(06→07)와 완전히 같은 그림
  소규모는 agent 단독(직행)으로 충분 — 층은 필요가 정당화 (07)
```

## 5. 샘플링의 배치 (04·cncf 12의 실전화)

```
head (SDK에서): Instrumentation의 sampler
  parentbased_traceidratio 0.25 — root에서 25% 결정, 자식은 부모 따름
  (parentbased가 핵심: 전 서비스가 같은 결정 — 아니면 트레이스가 구멍남)

tail (gateway에서): tail_sampling processor
  policies: 에러는 100%, p99 초과 지연 100%, 나머지 5%...
  ★ 왜 gateway인가: 판정하려면 trace의 모든 span이 한곳에 모여야
    → 로드밸런싱도 trace_id 기반이어야 (loadbalancing exporter)
  비용: 판정까지 버퍼(메모리) — 07의 집계층 비용과 동일 계열

실전: head(기본율로 볼륨 통제) + tail(에러·느린 것 부스트) 조합
  "개수는 메트릭, 사례는 트레이스"(04) — 샘플링 후 트레이스로 카운트 금지
```

## 6. 소스/도구에서 확인하기

- OTel Operator: opentelemetry.io/docs/kubernetes/operator
- Collector: opentelemetry.io/docs/collector (processors·tail_sampling)
- 자동 계측 언어별 문서 (지원 라이브러리 목록 확인 습관)
- cncf 12(스펙·시맨틱 컨벤션·샘플링 이론)

## 요약 카드

| 질문 | 답 |
|------|----|
| 자동 계측 범위? | 경계(HTTP·DB·gRPC·메시징) 공짜 — 내부 단계·커스텀 속성은 수동 |
| Operator 주입 실체? | admission webhook이 init 컨테이너+환경변수 주입 (Java/Python/Node) |
| Go는? | 런타임 주입 불가 — 라이브러리 통합 방식 (제로 코드 아님) |
| Collector 문법? | receiver→processor(→memory_limiter 첫!)→exporter, 신호 3종 한 설정 |
| 3패턴? | sidecar(격리·무거움)·agent DS(수집 표준)·gateway(정책·tail 샘플링) |
| 실전 조합? | app→agent→gateway = 로그의 Bit→Fluentd와 동형 (사상은 하나) |
| tail 샘플링 위치? | gateway — trace 전체 span이 모여야 판정 (trace_id 기반 LB) |
| head 샘플링 핵심? | parentbased — 전 서비스 같은 결정 (아니면 트레이스 구멍) |
