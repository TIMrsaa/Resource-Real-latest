# 자가 점검 퀴즈

**Q1.** SPIFFE와 SPIRE의 관계는? SPIFFE ID·SVID·Trust Bundle은 각각 무엇인가요?

**Q2.** IP 주소와 공유 시크릿이 워크로드 신원으로 부적합한 이유는? SPIFFE는 이를 어떻게 해결하나요?

**Q3.** "어테스테이션"이란 무엇인가요? "주장"과 "증명"의 차이를 설명하세요.

**Q4.** 부트스트랩 신뢰 문제("turtles all the way down")와 SPIRE의 답은? 07의 무엇과 같은 통찰인가요?

**Q5.** 노드 어테스테이션과 워크로드 어테스테이션의 차이와 각각의 방법은?

**Q6.** 앱이 SVID를 받는 방법(Workload API)이 22의 시크릿 전파 문제를 어떻게 회피하나요?

**Q7.** SPIFFE가 07의 신원 축(OIDC·keyless·Istio mTLS·cert-manager)을 어떻게 통일하나요?

**Q8.** 대부분의 조직이 SPIRE를 직접 운영하지 않는 이유와, 직접 운영하는 경우는?

---

## 정답

**A1.** SPIFFE는 표준(워크로드 신원이 무엇이고 어떻게 표현되나 — SPIFFE ID·SVID·Workload API 명세)이고 SPIRE는 그 표준의 프로덕션 구현(server·agent·어테스테이션)입니다. SPIFFE ID: `spiffe://<trust-domain>/<path>` 형식의 워크로드 이름(24 Istio mTLS의 그 신원). SVID(SPIFFE Verifiable Identity Document): 실제 신원 문서로 X.509 인증서(SAN에 SPIFFE ID) 또는 JWT. Trust Bundle: SVID를 검증하는 신뢰 앵커(루트 CA/공개키 — 19의 CA 번들).

**A2.** IP 주소: K8s에서 Pod IP는 계속 바뀌고 스푸핑(위조)이 가능합니다. 공유 시크릿: 유출되면 그것을 아는 누구나 신원을 도용할 수 있고, 시크릿을 안전하게 전달하는 것 자체가 부트스트랩 문제입니다. SPIFFE는 암호학적으로 검증 가능한 신원 문서(SVID)를 워크로드에 발급해 해결합니다 — Pod 재생성·IP 변경에도 신원은 불변(22의 Cilium identity와 같은 문제의식), 공유 시크릿이 아니라 각자의 검증 가능한 인증서라 하나 유출돼도 그 워크로드 하나만 영향받고(blast radius 최소), 어테스테이션으로 발급되어 위조가 불가능합니다.

**A3.** 어테스테이션은 워크로드의 신원을 플랫폼의 검증 가능한 속성으로 증명하는 과정입니다. "주장": 워크로드가 "나는 payment 서비스야"라고 스스로 말하는 것(API 키 제시 등) — 시크릿 유출 시 누구나 행세 가능. "증명": 워크로드는 아무것도 주장하지 않고 Workload API를 호출할 뿐이며, Agent가 그 프로세스의 커널 수준 속성(어느 Pod의 SA·namespace·labels인지, uid/cgroup 등)을 검증해 Server의 등록 항목과 대조합니다 — 커널·플랫폼이 그 프로세스의 실체를 증명하므로 워크로드가 거짓말할 수 없습니다(위조 불가).

**A4.** 문제: 워크로드에게 신원을 주려면 그것이 진짜인지 확인해야 하고, 확인하려면 뭔가를 신뢰해야 하며, 그 신뢰는 또 어디서 오나 — 무한 후퇴. 부트스트랩 시크릿을 미리 심는 전통적 답은 "그 시크릿을 어떻게 안전하게 전달?"이라는 같은 문제를 낳습니다. SPIRE의 답: 신뢰의 사슬을 플랫폼의 기존 신뢰에 뿌리내립니다 — 노드 어테스테이션에서 AWS Instance Identity Document(AWS가 서명)나 K8s Projected SA Token(API 서버가 검증)을 씁니다. "클라우드가 자기 인스턴스를 아는 것", "K8s가 자기 Pod의 SA를 아는 것"이 신뢰의 바닥입니다. 07의 OIDC와 같은 통찰(부트스트랩 시크릿을 없애고 플랫폼이 이미 아는 신원을 활용).

**A5.** 노드 어테스테이션: 그 노드 자체가 진짜인지 증명 — k8s_psat(K8s Projected SA Token을 API 서버가 검증), aws_iid(EC2 Instance Identity Document를 AWS가 서명), gcp_iit/azure_msi(클라우드별), join_token(수동 부트스트랩). 워크로드 어테스테이션: 그 노드 위의 프로세스가 누구인지 증명 — k8s selector(Pod의 namespace·SA·labels), unix(프로세스 uid/gid/path), docker(컨테이너 속성). Agent가 노드를 먼저 증명받고(노드 SVID), 증명된 노드 위에서 워크로드를 커널 속성으로 증명하는 신뢰의 사슬입니다.

**A6.** 앱은 Workload API(유닉스 소켓)에서 SVID를 받습니다 — 시크릿 파일이나 환경변수가 아닙니다. 22에서 배운 시크릿 전파 문제(volume subPath는 갱신 안 됨, env는 재시작 전까지 옛 값, 앱이 파일을 한 번만 읽음)를 회피합니다: SDK가 소켓에서 최신 SVID를 받고 만료 전 자동으로 새 SVID를 push받아 갱신합니다. 파일 마운트의 갱신 전파 문제가 없고, 짧은 수명 SVID가 소켓을 통해 무중단으로 회전되므로 "인증서 갱신이 앱에 반영 안 되는" 문제가 구조적으로 해결됩니다.

**A7.** SPIFFE ID는 24(Istio)의 mTLS 신원이 이미 쓰는 그 형식이고, 21(keyless)의 OIDC 신원, 07의 OIDC와 같은 "검증 가능한 신원" 계열입니다. SPIFFE의 통일: Istio가 사이드카 mTLS 신원으로 SPIFFE ID를 쓰고(istiod가 SPIRE 역할 또는 통합), Envoy가 SDS로 SVID를 수신하며, cert-manager(19)가 csi-driver-spiffe로 SVID를 인증서로 제공합니다 — 서비스 메시·서명·클라우드 접근이 같은 "검증 가능한 워크로드 신원"을 공유하게 됩니다. 커리큘럼 전체가 반복한 "비밀번호(공유 시크릿) → 신원 증명(검증 가능·각자의 것)"의 종착점이며 "공유 시크릿의 종말"입니다.

**A8.** 대부분의 조직은 메시(24 Istio)를 통해 SPIFFE 표준의 신원을 간접적으로 씁니다 — istiod가 SPIFFE ID를 발급하므로 SPIRE를 직접 운영할 필요가 없고, SPIRE Server가 신원의 SPOF(가용성·보안 핵심)이자 운영 부담(또 하나의 중요 인프라)이기 때문입니다. 직접 운영하는 경우: 메시 밖 워크로드(VM·레거시·다양한 플랫폼)에도 통일된 신원이 필요할 때, 멀티 클라우드·멀티 클러스터 페더레이션(경계를 넘는 워크로드 신원), 세밀한 어테스테이션 정책, 신원을 메시에 종속시키지 않으려는 플랫폼 팀. 신원은 보안의 척추이므로 SPIRE를 직접 운영한다는 것은 그 척추를 직접 세우는 것이고, 그만큼 Server·Trust Bundle의 가용성·보안이 전체의 전제가 됩니다.
