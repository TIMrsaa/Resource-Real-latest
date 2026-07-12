# 자가 점검 퀴즈

**Q1.** istiod의 세 역할은? 각각이 데이터플레인(사이드카)과 어떻게 관계하나요?

**Q2.** "메시의 마법"을 23의 지식으로 분해하세요. VirtualService/DestinationRule은 각각 Envoy의 무엇이 되나요?

**Q3.** 사이드카 주입은 어떻게 일어나며, "코드 수정 불필요"의 기술적 비결은?

**Q4.** mTLS를 STRICT로 바로 켜면 안 되는 이유와 올바른 마이그레이션 순서는?

**Q5.** AuthorizationPolicy의 집행 지점과 신원의 근거는? 22의 무엇과 같은 문제인가요?

**Q6.** ambient 모드의 두 컴포넌트와 각 역할은? 이것이 22의 어떤 원칙을 아키텍처로 구현하나요?

**Q7.** 메시 관측의 카디널리티 위험과 방어책은?

**Q8.** 메시 도입 판단의 핵심 질문과, ambient가 그 저울을 어떻게 바꾸나요?

---

## 정답

**A1.** ① xDS 서버: K8s 상태와 Istio CRD를 watch해 Envoy 설정으로 번역하고 사이드카에 push(23의 컨트롤플레인). ② CA(인증서 기관): 각 워크로드에 SPIFFE ID 기반 인증서를 발급(mTLS용). ③ 사이드카 주입: MutatingWebhook으로 istio-injection=enabled 네임스페이스의 새 Pod에 Envoy 컨테이너를 자동 삽입. 데이터플레인(사이드카 Envoy)은 istiod가 밀어넣는 설정대로 트래픽을 처리하고, istiod가 발급한 인증서로 mTLS를 하며, istiod의 webhook에 의해 주입됩니다 — 즉 istiod가 데이터플레인의 설정·신원·존재를 모두 관장합니다.

**A2.** "마법" = 23의 Envoy 기능(라우팅·mTLS·복원력·통계) + 그것을 K8s 리소스로부터 자동 설정하는 번역기(istiod). VirtualService → Envoy의 route configuration(경로·헤더·가중치·미러 — RDS), DestinationRule → Envoy의 cluster(LB 정책·아웃라이어 감지·서브셋·mTLS 모드 — CDS). Gateway → listener(LDS). 즉 CRD는 istiod에서 Envoy 설정으로 번역되어 사이드카의 config_dump에 나타납니다(lab-01에서 90/10 가중치가 weighted cluster로 번역된 것을 확인).

**A3.** istio-injection=enabled 라벨이 붙은 네임스페이스의 Pod 생성 시 MutatingWebhook이 개입해 Envoy 사이드카 컨테이너와 init 컨테이너를 Pod 스펙에 추가합니다. init 컨테이너가 iptables로 Pod의 모든 인/아웃 트래픽을 사이드카로 리다이렉트합니다 — 앱은 자기 트래픽이 사이드카를 경유하는 것을 모릅니다(투명한 가로채기). 이것이 "코드 수정 불필요"의 비결입니다: 앱은 평소대로 통신하고, 사이드카가 그 트래픽을 가로채 mTLS·라우팅·관측을 적용합니다.

**A4.** STRICT는 사이드카 없는 평문 통신을 전면 거부하므로, 아직 사이드카가 주입되지 않은 워크로드·메시 밖 서비스(레거시 DB, 외부 API)·주입 안 된 네임스페이스와의 통신이 즉시 끊깁니다. 올바른 순서: PERMISSIVE(평문+mTLS 모두 수용)로 시작 → `istioctl proxy-config`로 전체 워크로드에 사이드카·mTLS가 적용됐는지 확인 → 그 후 STRICT로 전환. 07의 audit→enforce, 19의 인증서 전파와 같은 점진적 이행 곡선입니다.

**A5.** 집행 지점은 사이드카 Envoy의 rbac(인가) 필터(23의 필터 체인)입니다. 신원의 근거는 mTLS 인증서에 담긴 SPIFFE ID(spiffe://cluster.local/ns/<ns>/sa/<serviceaccount>) — IP가 아니라 워크로드 신원으로 "누가 무엇을(메서드·경로)"을 판정합니다. 22의 Cilium L7 정책과 같은 문제(L7 인가, 워크로드 신원 기반)이고 구현만 다릅니다(Istio는 사이드카 Envoy, Cilium은 노드 Envoy 경유) — 48에서 비교합니다.

**A6.** ztunnel(DaemonSet, 노드당 하나): L4 — mTLS와 L4 인증을 노드 단위로 처리, Rust로 작성되어 가볍습니다. waypoint(선택적 Deployment): L7 — VirtualService·L7 AuthorizationPolicy 등 HTTP 단위 기능을 네임스페이스/서비스 단위로 처리. 22(Cilium)의 "L7은 필요한 곳에만" 원칙을 아키텍처로 구현한 것입니다 — 대부분의 워크로드는 L4 mTLS만 필요하므로 ztunnel만으로 충분하고, L7 기능이 실제 필요한 곳에만 waypoint를 배포해 비용을 지불합니다.

**A7.** istio_requests_total 등이 source × destination × response_code × response_flags × ... 조합마다 시계열을 생성하고, 사이드카마다 이 세트가 있어 서비스 수에 곱해집니다 — 11·23의 카디널리티 폭발이 메시 규모로 확대되어 Prometheus를 죽일 수 있습니다. 방어: telemetry API로 불필요한 차원(source_version 등) 억제, Prometheus metric_relabel_configs로 방어선(11), per-service 대신 집계 레벨 우선. 메시의 자동 관측은 공짜가 아닙니다.

**A8.** 핵심 질문: mTLS·트래픽 관리·관측 중 몇 개가 실제 요구인가 — 1개면 더 가벼운 대안(Cilium 투명 암호화, Argo Rollouts+Gateway API)이 낫고, 3개가 겹치고 그 복잡도를 운영할 팀이 있을 때 메시가 답입니다. ambient가 저울을 바꾸는 방식: 사이드카 모델은 모든 서비스가 full Envoy 비용을 지불하지만, ambient는 L4(ztunnel, 가벼움)와 L7(waypoint, 선택적)을 분리해 "mTLS만 필요한 대다수"의 비용을 크게 낮춥니다 — 즉 메시의 진입 비용을 낮춰 저울을 메시 쪽으로 조금 옮깁니다(특히 mTLS가 주 요구일 때).
