# 자가 점검 퀴즈

**Q1.** 자동 계측이 공짜로 주는 것과 수동이 필요한 것은? 80/20 전략이란?

**Q2.** Operator 주입의 실체(메커니즘)와 주입 실패의 단골 원인 세 가지는?

**Q3.** 언어별 "제로 코드" 가능 범위의 차이는? 폴리글랏 계측 계획에 주는 함의는?

**Q4.** Collector 파이프라인의 구성과 06(Fluent Bit)과의 대응은? memory_limiter가 첫 processor여야 하는 이유는?

**Q5.** 배포 3패턴의 트레이드오프와 표준 조합은? 로그 파이프라인과의 구조적 동형성은?

**Q6.** tail 샘플링은 왜 gateway에서만 가능한가? 다중 replica 시의 전제는?

**Q7.** head 샘플링에서 parentbased가 핵심인 이유는? 정책 불일치의 결과는?

**Q8.** "관측을 켜자 느려진" 사고의 세 원인과 재설계 네 가지는?

---

## 정답

**A1.** 자동이 공짜로 주는 것: 경계의 span — HTTP 서버/클라이언트(수신·발신), DB 드라이버(쿼리), gRPC, 메시징 클라이언트(전파 포함 — 04의 큐 끊김을 해결) — 표준 시맨틱 컨벤션 속성과 함께. 수동이 필요한 것: 비즈니스 로직 내부 단계의 span(예: "재고 계산" 구간), 커스텀 속성(주문 금액대·테넌트 등 조사용 차원), 비표준 라이브러리·자체 프로토콜. 80/20 전략: 자동 계측으로 서비스 경계 80%를 덮고, 조사 가치가 높은 핵심 경로에만 수동 span·속성을 20% 보강합니다.

**A2.** 실체: Instrumentation CRD에 정의(exporter·propagator·sampler·언어별 이미지)를 두고, Pod template에 어노테이션(inject-java 등)을 붙이면 Operator의 admission webhook이 Pod 생성 시 spec을 변형합니다 — init 컨테이너로 에이전트를 복사하고 환경변수(JAVA_TOOL_OPTIONS, OTEL_*)를 주입해, 앱 프로세스가 뜰 때 에이전트가 계측을 심습니다(마법이 아니라 웹훅+env). 실패 단골: ① 어노테이션을 Deployment 메타데이터에(Pod template이어야 함), ② Operator/웹훅보다 먼저 뜬 Pod(재배포 필요)·웹훅 장애 시 조용한 미주입, ③ 언어 불일치(Go 앱에 inject-java). 확인은 물증으로: init 컨테이너·OTEL_* env 존재.

**A3.** Java(-javaagent 런타임 주입, 가장 강력)·Python(부트스트랩 래핑)·Node(require 훅)는 제로 코드 주입이 잘 되지만, Go는 컴파일 언어라 런타임 주입이 불가능해 라이브러리 통합(otelhttp 등 — 코드 수정)이 기본입니다. 함의: "전 서비스에 어노테이션만 붙이면 끝"이라는 계획은 폴리글랏에서 깨집니다 — 언어별로 도입 트랙을 나눠(JVM/Python/Node는 주입, Go는 코드 작업 티켓) 계획하고, 전파 형식(W3C)만은 전 언어에서 통일해야 합니다.

**A4.** 구성: receivers(어떻게 받나 — otlp 등) → processors(순서 있는 가공 — memory_limiter·k8sattributes·batch·tail_sampling) → exporters(어디로 — tempo·prometheusremotewrite·loki), service.pipelines에서 신호 3종(traces/metrics/logs)별로 조립. 06과의 대응: receiver=INPUT, processor=FILTER, exporter=OUTPUT — 파이프라인 사상은 동일하고, 차이는 Collector가 신호 3종을 한 설정에서 다룬다는 것(신호 통합 게이트웨이의 근거). memory_limiter가 첫이어야 하는 이유: 뒤의 processor들이 메모리를 쓰기 전에 수신 단계에서 한도를 걸어 거부해야 폭주 시 Collector 자신이 OOM으로 죽는 것(수집기가 먼저 죽는 패턴)을 막습니다 — 자기 보호가 모든 가공에 앞섭니다.

**A5.** sidecar(Pod마다): 완전 격리·앱과 동일 생명주기가 장점, Pod 수만큼 리소스가 단점 — 강한 격리 요구의 특수 케이스만. agent(DaemonSet): 앱이 노드 로컬로 던져 홉 최소, k8sattributes에 유리, 노드 수만큼 자동 확장 — 수집층의 표준. gateway(중앙 Deployment): tail 샘플링·백엔드 인증·멀티 백엔드 라우팅의 집중 — 대신 새 운영점(HA·버퍼·역류, 07의 교훈). 표준 조합: 앱→agent→gateway→백엔드. 동형성: 로그의 Bit(노드 수집)→Fluentd(중앙 정책)와 완전히 같은 2층 구조 — "가까이서 받고, 가공하고, 중앙에서 정책"이라는 수집기의 사상은 신호가 달라도 하나입니다.

**A6.** tail 샘플링은 trace가 끝난 뒤 전체를 보고 판정(에러 있나요? 총 지연이 임계 초과인가요?)하므로, **같은 trace의 모든 span이 한 프로세스에 모여 있어야** 합니다. agent(노드별)에 두면 A의 span은 노드1에, B의 span은 노드2에 흩어져 판정이 반쪽이 됩니다 — 그래서 span이 집결하는 gateway에서만 가능합니다. 다중 replica 전제: gateway가 여러 개면 같은 trace가 같은 replica로 가도록 **trace_id 기반 로드밸런싱**(loadbalancing exporter를 앞단에)이 필요합니다 — 아니면 "에러 100% 정책인데 에러 trace가 반만 남는" 현상이 납니다. 비용은 decision_wait 동안의 버퍼 메모리.

**A7.** parentbased는 "부모 span의 샘플링 결정을 자식이 따른다"는 것으로, root(진입점)에서 한 번 결정하면 그 trace의 전 서비스가 같은 결정을 공유합니다 — 이래야 한 trace가 통째로 남거나 통째로 버려집니다. 불일치(서비스마다 다른 비율·parentbased 아님)의 결과: 한 trace 안에서 A는 버리고 B는 남겨 **구멍 난 트레이스**(간트에 빈 구간)가 되고, 이는 04의 전파 끊김과 비슷한 조사 불능을 만듭니다. 구조적 예방: Instrumentation CRD 값을 전사 통일하고, 비율 조정은 root에서만.

**A8.** 원인: ① 100% 샘플링 — 모든 요청이 span 생성·직렬화·전송 비용을 짐 + 저장 비용 4배 예고, ② 동기 export·gateway 직행 — span 전송이 요청 경로에 가산되고 네트워크 왕복도 김, ③ Collector 무방비 — memory_limiter 없음·replicas 1로 피크마다 OOM, 트레이스 유실 + 앱 재시도가 앱 스레드까지 잠식(역류). 재설계: ① 샘플링 전략 — head parentbased 10% 통일 + gateway tail로 에러·느림 100% 부스트(볼륨 1/10, 가치 유지), ② agent 층 추가 — 앱은 localhost 비동기 export, ③ Collector 방어선 — limiter 전면·replicas 2+·자기 메트릭 알림, ④ 오버헤드 예산 명문화 — "p99 +2% 이내"를 부하 테스트로 도입 게이트에. 교훈: 계측은 공짜가 아니며, 쉬워진 도입이 설계 없는 도입이 되면 관측이 서비스를 해칩니다.
