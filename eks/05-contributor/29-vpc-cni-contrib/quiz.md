# 자가 점검 퀴즈

**Q1.** vpc-cni의 두 바이너리와 각각의 수명·책임·통신 방법은?

**Q2.** 두 바이너리를 분리한 설계 이유와, 그것이 07의 어떤 개념을 정당화하는가요?

**Q3.** Pod 생성 시 CNI ADD 요청의 여정을 5단계로 서술하세요.

**Q4.** 07(warm pool), 16(고갈 에러), 18(veth/route)의 코드 좌표를 각각 대라.

**Q5.** 실재하지 않는 `169.254.1.1`이 Pod의 기본 게이트웨이로 동작하는 원리는? 코드의 어디서 확인하나요?

**Q6.** 네트워킹 코드가 클러스터 없이 단위 테스트되는 비결과, 28에서 본 같은 사상은?

**Q7.** "IP는 할당됐는데 Pod가 통신 불가" — 어느 바이너리를 의심하고 어느 로그를 보나요?

**Q8.** 이 저장소에서 "가장 환영받는 첫 기여"가 관측성 개선인 이유 세 가지는?

---

## 정답

**A1.** ① **ipamd** — aws-node DaemonSet 안의 장수 데몬. EC2 API와 대화해 ENI/IP를 확보하고 warm pool·재고 장부(datastore)를 유지. gRPC 서버. ② **CNI 플러그인**(`/opt/cni/bin/aws-cni`) — kubelet이 Pod마다 실행하는 단명 프로세스. ipamd에 gRPC로 IP를 요청하고 veth·netns·host route를 설정한 뒤 종료.

**A2.** 느리고 실패할 수 있는 **EC2 API 호출**을 Pod 생성이라는 지연 민감 경로에서 떼어내기 위해. 그래서 ipamd가 IP를 **미리** 확보해둬야 하고 — 이것이 warm pool(07)의 존재 이유입니다. warm이 없으면 모든 Pod 생성이 EC2 API 왕복을 기다립니다.

**A3.** ① kubelet/containerd가 CNI ADD로 플러그인 실행 → ② 플러그인이 gRPC로 ipamd에 AddNetwork 요청 → ③ ipamd가 datastore에서 IP 할당(부족하면 비동기로 EC2 호출 예약, 재고 0이면 실패 반환) → ④ 플러그인이 veth 쌍 생성 + Pod netns에 IP/기본 라우트 설정 → ⑤ 호스트에 Pod IP의 /32 host route 추가 후 프로세스 종료.

**A4.** warm pool 판정·보충: `pkg/ipamd/ipamd.go`의 `isDatastorePoolTooLow`/`increaseDatastorePool`. 고갈 에러: `pkg/ipamd/datastore`의 할당 함수("no available IP addresses"). veth·host route: `cmd/routed-eni-cni-plugin/driver/driver.go`의 `SetupPodNetwork`(netlink Route 추가 포함).

**A5.** 링크 로컬 주소를 게이트웨이로 두고, **정적 ARP 항목(및 proxy_arp)** 으로 그 주소의 MAC을 호스트 쪽 veth로 고정합니다 — Pod는 "게이트웨이가 있다"고 믿고 프레임을 보내며, 그것이 곧장 호스트 veth에 도달합니다. 확인: `driver.go`의 neigh/ARP 설정 부분(18 lab-01 Step 2에서 본 그 한 줄의 정체).

**A6.** netlink(커널 조작)와 EC2 API 호출을 **인터페이스로 감싸고 mock을 주입**하기 때문 — `make unit-test`가 root·클러스터·AWS 없이 돕니다. 28의 **fake CloudProvider**(Karpenter 코어 테스트)와 같은 사상: 외부 세계를 인터페이스 뒤로 숨겨 테스트 가능하게.

**A7.** **CNI 플러그인** 쪽을 의심합니다(IP 할당은 ipamd가 이미 성공시켰습니다 — veth/route/netns 설정이 문제). 로그는 aws-node Pod 로그가 아니라 노드의 파일: `/var/log/aws-routed-eni/plugin.log` (ipamd 로그는 `ipamd.log`).

**A8.** ① **위험이 낮습니다** — Pod 생성 경로의 로직을 바꾸지 않으므로 전면 장애 위험이 없습니다. ② **운영 가치가 즉시** 있습니다 — 16에서 우리가 손으로 조사한 것을 로그·메트릭이 알려줍니다(모든 사용자에게 이득). ③ **이해도의 증명**입니다 — 어디에 무엇을 노출해야 유용한지 아는 사람은 코드를 읽은 사람이고, 그 신뢰가 다음 PR의 리뷰 속도를 결정합니다.
