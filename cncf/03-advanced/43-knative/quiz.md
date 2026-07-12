# 자가 점검 퀴즈

**Q1.** Knative Serving이 일반 Deployment 대비 제공하는 서버리스 추상은? Service 하나가 무엇을 대체하나요?

**Q2.** scale-to-zero의 메커니즘(Activator·KPA)은? 0→1 흐름을 설명하세요.

**Q3.** KPA와 HPA(08)의 차이는? 왜 KPA가 0까지 갈 수 있나요?

**Q4.** Revision과 트래픽 분할로 카나리·롤백을 하는 방식은? 08과 어떻게 대응하나요?

**Q5.** Knative Eventing의 구성(Source·Broker·Trigger·Sink)과 40(CloudEvents)의 관계는?

**Q6.** Knative와 KEDA(18)의 정확한 차이는? 언제 무엇을 쓰나요?

**Q7.** 콜드 스타트란? 무엇이 그것을 악화시키고 어떻게 완화하나요?

**Q8.** "콜드 스타트 체인" 사고의 원인과 교훈은? scale-to-zero는 어떤 워크로드에 맞나요?

---

## 정답

**A1.** Knative Serving은 scale-to-zero(요청 없으면 Pod 0)·자동 오토스케일(0→N)·불변 리비전·트래픽 분할·자동 URL을 제공합니다. Service 하나가 일반적으로 따로 만들어야 할 Deployment+Service+HPA+Ingress+(카나리는 별도 메시)를 한꺼번에 대체합니다 — "HTTP 요청을 받는 서버리스 컨테이너"를 YAML 몇 줄로 얻는 추상입니다.

**A2.** Activator(항상 떠 있으며 요청을 붙잡고 버퍼링), KPA(Autoscaler, 요청량으로 Pod 수 결정), Queue-Proxy(각 Pod 사이드카, 동시성 측정). 0→1 흐름: ① 요청 도착, Pod 0이라 Activator로 라우팅 → ② Activator가 요청을 버퍼하고 KPA에 스케일 업 신호 → ③ KPA가 Pod 1개 생성, 준비 대기 → ④ Pod Ready → Activator가 버퍼한 요청 전달 → ⑤ 이후는 Activator 우회, Pod로 직접. ①~④ 사이가 콜드 스타트 지연입니다.

**A3.** HPA(08)는 CPU·메모리 기반이고 최소 1을 유지합니다(0으로 못 감 — 메트릭을 낼 Pod가 있어야). KPA는 동시성(concurrency)·RPS(요청) 기반이고 0까지 갑니다. KPA가 0으로 갈 수 있는 이유는 Activator가 Pod 대신 요청을 받아주기 때문입니다 — Pod가 0이어도 Activator가 요청을 붙잡아 KPA에 스케일 신호를 주고 Pod를 띄웁니다. 즉 "Pod가 없어도 요청을 받을 주체(Activator)"가 있어 0이 가능합니다.

**A4.** 배포할 때마다 불변 Revision(hello-00001, -00002...)이 생기고 옛 것도 남습니다. Route의 traffic에서 각 Revision에 percent를 배분합니다(revision-1: 90%, revision-2: 10% → 카나리). 문제없으면 10→50→100으로 올리고, 문제 생기면 새 Revision을 0%로(즉시 롤백, 옛 Revision이 남아 있으므로). 08의 배포 전략과 대응: 블루그린(100%→전환), 카나리(점진 %), 롤백(옛 Revision으로 %복귀) — 08에서 배운 것이 Knative에 내장돼 YAML % 변경(GitOps 14·15)으로 됩니다.

**A5.** Source(이벤트 발생원 → CloudEvents로 변환, PingSource·KafkaSource 등), Broker(이벤트 버스, 이벤트 수신·전달), Trigger(필터+구독, CloudEvents type·source로 소비자 라우팅), Sink(소비자, Knative Service 등). 40(CloudEvents)과의 관계: Eventing이 라우팅하는 이벤트가 바로 40의 CloudEvents 봉투 형식이고, Trigger의 필터가 CloudEvents의 `type`·`source` 속성으로 라우팅합니다 — 40에서 event-display로 받아본 것이 Sink였고, 이 모듈이 그 전체 경로(Broker·Trigger)를 완성합니다.

**A6.** KEDA(18)는 스케일러입니다 — 기존 Deployment를 이벤트 소스(Kafka lag·큐 길이 등 50+)로 0↔N 스케일하며 가볍습니다. Knative는 서버리스 플랫폼입니다 — 자체 Service를 HTTP 요청·CloudEvents로 스케일하고 리비전·트래픽·Eventing 라우팅까지 제공하며 무겁습니다. 둘 다 scale-to-zero·이벤트 스케일을 하지만, KEDA는 리비전·트래픽·라우팅이 없습니다. 선택: 기존 워크로드를 이벤트로 스케일만 하면 KEDA(가볍고 충분), 서버리스 플랫폼+트래픽 관리+이벤트 라우팅이면 Knative. 실무는 Knative Eventing 라우팅 + KEDA 스케일로 조합하기도 합니다.

**A7.** 콜드 스타트는 Pod가 0인 상태에서 요청이 와 Pod를 0→1로 띄우는 동안 첫 요청이 대기하는 지연입니다(이미지 풀 + 컨테이너 시작 + 앱 초기화의 합). 악화 요인: 큰 이미지(수GB), 느린 부팅(JVM 웜업·대형 프레임워크), 무거운 초기화(커넥션 풀). 완화: 작은 이미지(03 멀티스테이지·distroless), 빠른 시작 런타임(Go·Node), 지연 초기화 최소화, `minScale: 1`(최소 1 유지로 웜, scale-to-zero 포기), 예측 가능한 트래픽은 스케줄 사전 워밍(KEDA cron).

**A8.** 원인: 주말에 모든 서비스가 0으로 내려간 뒤 월요일 아침 일제 접속으로 서로 호출하는 체인(A→B→C)이 동시에 콜드 스타트 → 지연 누적(6~9초)이 타임아웃(5초)을 초과 → 실패·재시도 폭풍(24)이 더 많은 콜드 스타트를 유발 → 마비. 교훈: 서비스 체인에 일괄 scale-to-zero는 콜드 스타트가 누적·증폭되어 위험, 예측 가능한 트래픽엔 minScale:1이나 스케줄 사전 워밍, 타임아웃은 콜드 스타트 포함 최악 경로 고려, 재시도에 백오프·서킷 브레이커. scale-to-zero는 "0으로 가도 되는" 워크로드(배치·드문 이벤트·지연 감내 내부 도구)에만 맞고, 매일 확실히 쓰는 서비스나 지연 민감 API엔 부적합합니다.
