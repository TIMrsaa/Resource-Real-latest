# 자가 점검 퀴즈

**Q1.** Linkerd와 Istio의 데이터플레인 차이는? Linkerd가 Envoy를 안 쓴 근거와 대가는?

**Q2.** Linkerd control plane의 세 컴포넌트와 Istio istiod의 대응 관계는?

**Q3.** "자동 mTLS"가 Istio의 mTLS와 다른 점은? 신원의 근거는?

**Q4.** 골든 메트릭이란? linkerd viz의 네 도구(stat/top/tap/edges)는 각각 무엇을 하나요?

**Q5.** Linkerd가 카디널리티를 다루는 방식이 24의 무엇과 대비되나요?

**Q6.** Linkerd가 못 하는(또는 어려운) 것 세 가지는? 그것이 필요하면 무엇을 써야 하나요?

**Q7.** "단순함은 그 단순함이 충분할 때만 강점"을 사고 사례로 설명하세요.

**Q8.** 메시 선택 결정 트리를 요구·기존 스택·기능축으로 설명하세요.

---

## 정답

**A1.** Istio는 범용 프록시 Envoy(C++)를 사이드카로, Linkerd는 사이드카 전용으로 특화한 자체 프록시 linkerd2-proxy(Rust)를 씁니다 — Linkerd는 04의 Envoy 계보도에서 유일한 예외입니다. 근거: 사이드카에 필요한 것만 담아 작고(수 MB 대 수십 MB) 안전하며(Rust 메모리 안전) 설정 표면이 작습니다. 대가: Envoy의 방대한 기능(WASM 확장, ext_authz, 광범위한 프로토콜)을 포기 — 그것이 필요하면 Linkerd는 답이 아닙니다.

**A2.** destination(서비스 디스커버리·정책을 프록시에 제공 — istiod의 xDS 역할), identity(mTLS 인증서 발급 — istiod의 CA 역할), proxy-injector(사이드카 주입 webhook — istiod의 injection webhook). 즉 istiod의 세 역할(xDS·CA·주입)이 Linkerd에서는 세 컴포넌트로 나뉘어 있습니다. 차이: Linkerd는 xDS(Envoy 프로토콜)가 아니라 자체 gRPC API로 프록시와 통신합니다(전용 프록시라 Envoy 호환이 불필요).

**A3.** Istio는 PeerAuthentication CRD로 mTLS 모드(STRICT/PERMISSIVE)를 지정하고 PERMISSIVE→STRICT 마이그레이션이 명시적입니다. Linkerd는 설치와 주입만으로 메시 안 통신이 자동으로 mTLS가 되며 별도 CRD가 필요 없습니다("설정 없이 안전"). 신원의 근거는 ServiceAccount 기반(identity 컴포넌트가 SA별 인증서 발급) — Istio의 SPIFFE ID와 유사한 개념이나 자동입니다. 단 메시 밖(사이드카 없는) 통신은 평문이라는 것은 양쪽 다 같습니다.

**A4.** 골든 메트릭은 사이드카가 모든 트래픽을 관찰해 자동 생성하는 RED 메트릭 — 성공률(2xx·3xx 비율), RPS(초당 요청), 지연(p50/p95/p99). linkerd viz: stat(워크로드별 골든 메트릭 실시간), top(경로·요청별 실시간 집계 — 13의 조사 동선), tap(개별 요청의 실시간 스트림 — tcpdump-for-requests, mTLS 여부까지), edges(서비스 간 연결과 mTLS SECURED 상태).

**A5.** 24(Istio)에서 istio_requests_total의 방대한 차원(source×destination×code×flags×...)이 카디널리티 폭발을 일으켜 Prometheus를 죽일 수 있고, telemetry API로 차원을 억제해야 합니다. Linkerd는 골든 메트릭의 차원을 **의도적으로 억제**하는 방향으로 설계되어 있어(핵심 지표에 집중) 이 폭발 문제를 설계 단계에서 회피합니다 — "덜 하는 것도 설계"의 관측판입니다.

**A6.** ① 외부 인가 서비스 연동(ext_authz → OPA) — Istio는 Envoy 필터로 간단. ② WASM 플러그인 확장. ③ 세밀한 헤더 조작·복잡한 매칭·일부 비HTTP 프로토콜의 L7 처리. 이것들이 필요하면 Istio(사이드카 또는 ambient) 또는 Gateway API + Envoy를 써야 합니다. Linkerd의 단순함은 이런 고급 요구 앞에서 오히려 제약이 되며, "단순함은 그 단순함이 충분할 때만 강점"입니다.

**A7.** 사고 사례에서 B팀은 원하는 것이 mTLS와 메트릭뿐이라 Linkerd를 골랐고, 전담 인력 없이 운영이 편했습니다 — 요구가 단순했으므로 단순함이 강점이었습니다. 그러나 나중에 세밀한 프로토콜 라우팅이 필요한 서비스가 생기자 Linkerd로는 어려워 그 서비스만 별도 처리해야 했습니다 — 요구가 단순함의 범위를 넘는 순간 그 단순함이 한계가 됐습니다. 즉 단순함의 가치는 절대적이지 않고 요구와의 관계에서 정해집니다: 요구 ≤ 단순함의 범위이면 강점, 초과하면 제약. 그래서 요구가 커지는 순간을 대비한 이전 계획이 있어야 합니다(B팀의 교훈).

**A8.** ① 요구 개수: mTLS·트래픽관리·관측 중 1개면 가벼운 대안(Cilium 암호화, Argo Rollouts+Gateway API), 2~3개 겹치면 메시. ② 기존 스택: 이미 Cilium CNI면 Cilium Service Mesh(사이드카 없는 mTLS, 22) 검토. ③ 기능 축: 원하는 것이 "mTLS + 골든 메트릭 + 간단한 분할"이고 운영 최소화가 우선이면 Linkerd; 복잡한 트래픽 관리(세밀 라우팅·외부 인가·WASM)나 대규모 비용 최적화가 필요하면 Istio(사이드카/ambient). "더 많은 기능"이 우월이 아니며 운영하지 않을 기능은 부채입니다 — 둘 다 Graduated, 둘 다 옳고, 다른 질문에 답합니다.
