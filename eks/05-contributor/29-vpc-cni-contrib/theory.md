# 이론 — 두 바이너리, datastore의 장부, 그리고 veth 몇 줄

> **🌱 17세 눈높이 비유: 놀이공원의 팔찌 배부**
> - **ipamd** = 매표소 직원: 본사(EC2 API)에 전화해 팔찌 묶음(ENI의 IP들)을 미리 받아둡니다 — 전화는 느리니까 **미리**(warm pool). 재고 장부를 손에 들고 있습니다
> - **CNI 플러그인** = 입구 알바생: 손님(Pod)이 오면 매표소에 인터폰(gRPC)으로 "팔찌 하나"를 요청하고, 받은 팔찌를 손목에 채우고(veth 생성), 안내판에 이름을 적습니다(host route). 그리고 퇴근합니다 — 손님마다 새 알바생이 옵니다
> - 왜 나눴나: 본사 전화(느림·실패 가능)와 손목에 채우기(빠름·확실)를 분리해야, 손님 줄이 본사 전화 대기로 멈추지 않습니다
> - **prefix delegation** = 팔찌를 낱개가 아니라 16개들이 팩으로 받기 — 전화 횟수가 줄고 재고가 늘지만, **연속된 16개**여야 합니다

---

## 1. 저장소 지도

```
cmd/
  aws-vpc-cni/                  init 컨테이너 (호스트에 바이너리 설치, iptables 설정)
  routed-eni-cni-plugin/        ★ CNI 플러그인 (kubelet이 실행하는 단명 프로세스)
    cni.go                        ADD/DEL 진입점 — Pod 하나의 네트워크 생성/삭제
    driver/driver.go              ★ veth 쌍, netns, host route (18의 그 실체)
  egress-cni-plugin/            IPv6 egress 등 체인 플러그인

pkg/
  ipamd/                        ★ 장수 데몬
    ipamd.go                      메인 루프: ENI 관리, warm pool 유지 (07)
    datastore/                    ★★ IP 재고 장부 (메모리 자료구조)
    rpc_handler.go                gRPC 서버 — 플러그인의 요청 처리
  awsutils/                     EC2 API 래퍼 (ENI 부착, IP/prefix 할당)
  networkutils/                 노드 쪽 라우팅·iptables (SNAT 규칙 — 18 §3)
  ipamd/datastore/data_store.go   AssignPodIPv4Address / warm 계산의 핵심

scripts/  charts/  test/        빌드, 헬름 차트, e2e
```

## 2. 요청 하나의 여정 — Pod 생성 시

```
kubelet → containerd → CNI ADD 호출 (/opt/cni/bin/aws-cni)
  │
  ├ cmd/routed-eni-cni-plugin/cni.go: add()
  │    ├ gRPC → ipamd: AddNetwork(pod namespace/name)
  │    │     └ pkg/ipamd/rpc_handler.go → datastore.AssignPodIPv4Address()
  │    │           - 장부에서 사용 가능한 IP 하나 골라 "할당됨" 표시
  │    │           - warm pool이 부족해지면 비동기로 EC2 API 호출 예약
  │    │           - 재고 0이면 → "no available IP addresses" (16의 그 에러!)
  │    └ IP를 받아 driver.SetupPodNetwork():
  │          ① veth 쌍 생성 (호스트쪽 eniXXXX ↔ Pod netns의 eth0)
  │          ② Pod netns 안: IP 설정 + default via 169.254.1.1 (18 lab-01의 그 한 줄)
  │          ③ 호스트: Pod IP → veth의 /32 host route 추가 (18의 안내판)
  │          ④ (필요시) 규칙 기반 라우팅 테이블(다중 ENI일 때)
  └ 종료 (프로세스는 죽습니다)
```

**핵심 통찰**: 18에서 우리가 노드 안에서 본 host route와 veth는 `driver.go`의 수십 줄이 만든 것입니다. 그리고 07에서 본 warm pool은 `datastore`의 장부 상태입니다. 이론이 코드의 좌표를 갖는 순간, 디버깅이 추측에서 조사로 바뀝니다.

## 3. datastore — 07·16의 방정식이 사는 곳

```go
// 개념 구조 (pkg/ipamd/datastore)
type DataStore struct {
    eniPool map[string]*ENI      // ENI마다 IP(또는 prefix) 집합
    // 각 IP: assigned 여부, Pod 정보, 할당 시각
}

// 핵심 질의들
func (ds *DataStore) GetIPStats(af string) DataStoreStats   // total / assigned → awscni_* 메트릭
func (ds *DataStore) AssignPodIPv4Address(...) (string, ...) // 할당
func (ds *DataStore) FreeableIPs(eniID string) int           // 반납 가능량 (축소 판단)
```

- warm 계산: `ipamd.go`의 `nodeIPPoolReconcile`·`increaseDatastorePool` 등이 `WARM_IP_TARGET`/`MINIMUM_IP_TARGET`/`WARM_ENI_TARGET` 환경변수를 읽어 **부족분을 계산하고 EC2 API를 호출**합니다 — 16 theory §2의 표가 여기서 실행됩니다
- prefix delegation: 같은 장부가 개별 IP 대신 `/28` 블록을 단위로 관리(`ENABLE_PREFIX_DELEGATION`) — 16의 "연속 블록 필요"라는 제약이 EC2 API의 성질이지 코드의 선택이 아님을 확인할 수 있습니다
- 메트릭: `awscni_total_ip_addresses` / `awscni_assigned_ip_addresses` — 16 lab-01에서 알람에 쓴 그 값들이 이 장부의 직접 노출입니다

## 4. 플러그인 쪽 — 18의 몇 줄

```go
// cmd/routed-eni-cni-plugin/driver/driver.go (개념)
func (n *linuxNetwork) SetupPodNetwork(...) error {
    hostVeth, contVeth := createVethPairContext(...)   // ① veth 쌍
    // ② 컨테이너 netns 안에서:
    //    - eth0에 IP 설정
    //    - default route via 169.254.1.1 (링크 로컬 게이트웨이)
    //    - ARP 항목 고정 (게이트웨이는 실재하지 않습니다 — 트릭!)
    // ③ 호스트:
    //    - hostVeth에 /32 route: "이 Pod IP는 이 veth로"
    //    - 다중 ENI면 rule/table로 소스 라우팅
}
```

`169.254.1.1`이 실재하지 않는 주소인데 게이트웨이로 동작하는 이유(정적 ARP + proxy_arp)를 코드에서 확인하는 것이 이 파트의 백미입니다 — 18 lab-01 Step 2에서 본 그 한 줄의 정체.

## 5. 테스트 문화

```
make unit-test         # 클러스터 없이 — datastore, 계산 로직, gRPC 핸들러
                       # 네트워킹 부분은 mock netlink 인터페이스로 검증
make build-linux       # 바이너리
make docker            # 이미지 (배포는 신중히! — guide의 안전 수칙)
test/                  # e2e: 실제 EKS 클러스터 필요, CI에서 실행
```

네트워킹 코드가 단위 테스트 가능한 비결: `netlink` 호출을 인터페이스로 감싸고 mock을 주입합니다(`pkg/networkutils`의 `NetLink` 인터페이스) — **28의 fake CloudProvider와 같은 사상**입니다. "외부 세계를 인터페이스 뒤로 숨겨 테스트 가능하게"는 Go 컨트롤러 생태계의 공통 문법.

## 6. 기여 좌표 — 우리가 겪은 마찰이 코드의 어디인가

| 우리의 마찰 (모듈) | 코드 좌표 | 기여 아이디어 |
|-------------------|----------|-------------|
| "IP 할당 실패 이유가 불친절"(16) | `datastore`/`rpc_handler.go` 에러 경로 | 실패 로그에 서브넷 여유·warm 상태 포함 |
| "prefix 할당 실패가 IP 부족처럼 보임"(16) | `awsutils` prefix 할당부 | 파편화 실패를 구분되는 에러/메트릭으로 |
| "warm 설정의 효과를 알기 어려움"(07) | 메트릭 노출부 | warm pool 예약량 메트릭 추가 |
| "custom networking 시 max-pods 하락이 조용함"(16) | 문서/init 컨테이너 경고 | 문서 + 시작 시 경고 로그 |

**관측성 개선은 이 저장소에서 가장 환영받는 첫 기여입니다** — 위험이 낮고, 운영자(우리 자신)에게 즉시 도움이 되며, 코드 이해도를 증명합니다.

## 7. 소스/도구에서 확인하기

- 저장소: https://github.com/aws/amazon-vpc-cni-k8s — `docs/` 아래 설계 문서들이 훌륭합니다
- CNI 명세(모든 CNI 플러그인의 계약): https://github.com/containernetworking/cni/blob/main/SPEC.md
- `docs/cni-proposal.md`, `docs/prefix-and-ip-target.md` — 07·16의 원전
- `misc/max-pods-calculator.sh` — 05에서 쓴 그 스크립트의 출처

## 요약 카드

| 질문 | 답 |
|------|----|
| 두 바이너리? | ipamd(장수 데몬, EC2 API, 장부) + CNI 플러그인(단명, veth/route) |
| 왜 분리했나요? | 느린 EC2 API를 Pod 생성 경로에서 떼어내기 위해 → warm pool의 존재 이유 |
| 07·16의 코드 좌표? | `pkg/ipamd/datastore` (장부·warm 계산) |
| 18의 코드 좌표? | `cmd/routed-eni-cni-plugin/driver/driver.go` (veth·host route) |
| 네트워킹 단위 테스트 비결? | netlink를 인터페이스로 감싸고 mock 주입 |
| 가장 환영받는 첫 기여? | **관측성**(로그·메트릭) — 낮은 위험, 높은 운영 가치 |
| 절대 금지? | 공유 클러스터에 커스텀 CNI 배포 |
