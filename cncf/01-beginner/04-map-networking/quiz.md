# 자가 점검 퀴즈

**Q1.** 네트워킹 지도의 4+1층과 각 층의 대표 프로젝트를 말하세요.

**Q2.** CNI 선택의 세 축과, vpc-cni(eks 16)가 그 축에서 어디에 서는지 설명하세요.

**Q3.** "CNI가 없으면 노드가 NotReady"인 이유(lab-02 Step 1)와, NetworkPolicy가 "조용히 무시"될 수 있는 구조적 이유는?

**Q4.** Envoy가 공용 부품이 된 구조적 이유와, 그 계보에 속한 프로젝트 셋을 들어라.

**Q5.** iptables 기반과 eBPF 기반의 구조 차이와, eBPF 도입의 올바른 근거는?

**Q6.** Hubble의 관찰이 전통적 네트워크 모니터링과 구조적으로 다른 점은? (eks 18과 연결)

**Q7.** "Cilium vs Istio"가 잘못된 질문이 되는 경우와, 올바른 분해 순서는?

**Q8.** Gateway API가 Ingress를 대체하는 이유 두 가지와, 현실적 전환 경로는?

---

## 정답

**A1.** ① CNI(Pod 네트워크 시공): Cilium·Calico·Flannel·vpc-cni. ② DNS·디스커버리: CoreDNS(+원천으로 etcd, RPC로 gRPC). ③ 프록시·인그레스·게이트웨이: Envoy와 그 계보(Contour·Emissary·Envoy Gateway), 비Envoy(NGINX 등). ④ 메시: Istio·Linkerd·Cilium Mesh·Kuma. +1 지각 변동: eBPF — 층들을 관통하는 데이터 경로 재건축.

**A2.** ① 오버레이(VXLAN 캡슐화 — Flannel) vs 네이티브 라우팅(BGP — Calico / VPC 통합) ② NetworkPolicy 지원과 표현력(없음~L3/L4~L7) ③ kube-proxy 대체 여부(eBPF 계열의 성능·기능 통합). vpc-cni: 네이티브의 극단(Pod가 VPC의 실제 IP를 받는 시민 — 오버레이 없음, 대가는 IP 소진 방정식 — eks 16), 정책은 기본 제한적이라 Cilium 병용 조합이 실무에 존재.

**A3.** kubelet은 Pod 샌드박스에 네트워크(IP·인터페이스)를 붙이기 위해 CNI 플러그인을 호출합니다 — 플러그인이 없으면 Pod 네트워크 구성이 불가능하므로 노드가 Ready 조건을 충족하지 못합니다(CoreDNS부터 Pending). NetworkPolicy의 조용한 무시: 정책은 API 오브젝트로 저장될 뿐이고 집행자는 CNI입니다 — 미지원 CNI는 정책을 읽지 않으며, API 서버는 "집행되는지"를 검증하지 않으므로 에러 없이 장식이 됩니다. 검증은 차단의 실측뿐.

**A4.** Envoy는 설정을 파일이 아니라 동적 API(xDS)로 실시간 주입받는 L7 프록시 엔진 — 덕분에 다양한 컨트롤플레인이 "설정 생성기"로 그 위에 앉을 수 있었습니다(프록시를 다시 만들 필요 없이 — 02의 확장 지점 논리). 계보: Istio(메시 데이터플레인), Contour(인그레스), Emissary(API 게이트웨이), Envoy Gateway(Gateway API 구현), Kuma 등.

**A5.** iptables: Service마다 NAT 규칙 여러 개가 체인에 선형 추가 — 패킷마다 체인 순회, 규칙 수만 개 규모에서 조회·갱신 모두 병목. eBPF: 커널에 검증된 프로그램을 삽입, Service→백엔드를 해시맵 O(1) 조회 + 같은 지점에서 정책·관찰·암호화. 올바른 도입 근거: 증상(Service 수천 개의 갱신 지연, kube-proxy 병목, 정책·관찰 통합 요구) — "eBPF니까"는 근거가 아니고, 소규모에서는 iptables가 병목이 아닙니다. 성장 곡선의 어느 지점에서 증상이 올지 아는 것까지가 지도.

**A6.** 전통 모니터링은 데이터 경로 밖의 에이전트가 패킷을 복사·샘플링해 추측합니다(사각과 비용 — eks 18의 Flow Logs 고민). Hubble은 판정이 일어나는 그 지점(eBPF 데이터 경로)에서 플로우를 기록합니다 — "누가 누구에게, 어느 정책(POLICY_DENIED)이 떨궜나"가 판정 근거와 함께 남습니다. 관찰 = 집행 지점이라 추측이 아니라 사실이고, 추가 복사 비용이 최소입니다.

**A7.** Cilium은 CNI 층(+정책·관찰·부분 메시 기능), Istio는 메시 층 — 층이 달라 조합(둘 다 사용)이 흔하므로 "vs"는 메시 기능이 겹치는 좁은 영역에서만 성립합니다. 분해 순서: ① CNI는 무엇으로(선택 축 3개) ② 메시가 필요한가 — mTLS·트래픽 관리·관찰 중 실제 요구가 몇 개인가(eks 20) ③ 필요하다면 데이터플레인은(Envoy 사이드카/ambient vs Rust vs eBPF — 48의 비교). 층 순서로 물으면 조합 문제, 로고로 물으면 영원한 논쟁.

**A8.** ① 표현력 — 가중치·헤더 라우팅, TCP/gRPC 등 Ingress의 어노테이션 지옥을 표준 API로. ② 역할 분리 — Gateway(인프라팀 소유)와 HTTPRoute(앱팀 소유)의 리소스 분리(멀티팀 거버넌스 — cicd 24와 공명). Ingress는 유지보수 모드로 신규 기능이 오지 않습니다. 전환 경로: 전면 교체가 아니라 신규 서비스부터 Gateway API, 기존은 기능 요구 발생 시 — 컨트롤러의 Gateway API 구현 성숙도를 반기마다 확인.
