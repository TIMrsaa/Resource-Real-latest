# Lab 01 — 코드 투어: 07·16·18이 사는 줄을 찾아서

이론이 코드의 좌표를 갖는 순간, 디버깅은 추측이 아니라 조사가 됩니다. 우리가 사용자로 관찰한 현상들을 **소스에서 확인**합니다.

## Step 1. 클론과 첫 지형

```bash
mkdir -p ~/cni && cd ~/cni
gh repo clone aws/amazon-vpc-cni-k8s . && cd .

# 두 바이너리의 진입점 (theory §1)
ls cmd/
wc -l cmd/routed-eni-cni-plugin/cni.go pkg/ipamd/ipamd.go pkg/ipamd/datastore/data_store.go
```

✅ ipamd(수천 줄)와 플러그인(수백 줄)의 크기 차이가 역할을 말해줍니다 — 복잡성은 재고 관리(EC2 API와의 대화)에 있고, 플러그인은 짧고 확실한 일을 합니다.

## Step 2. 좌표 ① — 07의 warm pool이 계산되는 곳

```bash
# 환경변수가 읽히는 지점
grep -rn "WARM_IP_TARGET\|MINIMUM_IP_TARGET\|WARM_ENI_TARGET" pkg/ipamd/*.go | head -6

# 부족분 계산과 EC2 호출 예약
grep -n "func (c \*IPAMContext) nodeIPPoolReconcile\|func (c \*IPAMContext) increaseDatastorePool\|func (c \*IPAMContext) isDatastorePoolTooLow" pkg/ipamd/ipamd.go
```

읽을 것: `isDatastorePoolTooLow`가 "지금 재고가 목표보다 적은가"를 판정하고, `increaseDatastorePool`이 EC2 API를 부릅니다. **16 theory §2의 표(WARM_IP_TARGET의 트레이드오프)가 이 함수들의 동작 그 자체**입니다 — WARM_IP_TARGET을 낮추면 이 판정이 자주 참이 되고, Pod 생성 경로에서 EC2 호출을 기다리게 됩니다.

```bash
# 우리가 16 lab-01에서 알람에 쓴 그 메트릭이 나오는 곳
grep -rn "awscni_total_ip_addresses\|awscni_assigned_ip_addresses" pkg/ | head -4
```

## Step 3. 좌표 ② — 16의 "no available IP addresses"

```bash
# 그 에러 문자열을 추적 (사용자가 보는 메시지에서 코드로 역추적하는 훈련)
grep -rn "no available IP addresses" pkg/ | head -3
```

에러가 나는 함수를 열어보면 — 장부(datastore)에 여유가 없을 때 반환됩니다. 여기서 기여 아이디어가 보입니다(theory §6): **이 에러에 "현재 total/assigned, warm 설정, 마지막 EC2 호출 실패 사유"를 함께 담으면**, 16 lab-01에서 우리가 손으로 조사한 것을 로그가 한 번에 알려줍니다.

## Step 4. 좌표 ③ — 18의 veth와 host route

```bash
grep -n "func (n \*linuxNetwork) SetupPodNetwork\|createVethPairContext\|func setupVeth" cmd/routed-eni-cni-plugin/driver/driver.go | head

# 18 lab-01에서 Pod 안에 보인 그 게이트웨이
grep -rn "169.254.1.1\|gwIPv4\|GetGatewayIP" cmd/routed-eni-cni-plugin/driver/*.go | head -5
```

핵심 대목 — 실재하지 않는 게이트웨이가 동작하는 이유:

```bash
# 정적 ARP/proxy 설정 (링크 로컬 게이트웨이의 트릭)
grep -rn "neigh\|Neigh\|proxy_arp" cmd/routed-eni-cni-plugin/driver/driver.go | head -5

# 호스트 쪽 /32 라우트 추가 — "이 Pod IP는 이 veth로" (18 lab-01 Step 3의 실물)
grep -n "RouteReplace\|netlink.Route{" cmd/routed-eni-cni-plugin/driver/driver.go | head -5
```

✅ **18에서 노드에 들어가 `ip route`로 본 그 줄들이, 이 몇 줄의 Go 코드가 만든 것**입니다. 사용자로서 본 현상 → 개발자로서 읽는 원인. 커리큘럼이 여기서 한 바퀴를 돕니다.

## Step 5. gRPC 계약 — 두 바이너리의 국경

```bash
# 인터페이스 정의 (protobuf)
find . -name "*.proto" | head
grep -n "rpc AddNetwork\|rpc DelNetwork" rpc/rpc.proto 2>/dev/null || grep -rn "rpc AddNetwork" --include=*.proto .

# 서버(ipamd) 쪽 핸들러
grep -n "func (s \*server) AddNetwork" -A 12 pkg/ipamd/rpc_handler.go | head -18
```

✅ 28의 CloudProvider 인터페이스처럼, 여기서도 **경계가 명시적 계약**으로 표현돼 있습니다. 큰 시스템을 읽는 법은 언제나 같습니다 — 경계를 먼저 찾아라.

## Step 6. 설계 문서 — 저자들의 사고를 직접 읽기

```bash
ls docs/
# 특히:
head -40 docs/cni-proposal.md 2>/dev/null
head -30 docs/prefix-and-ip-target.md 2>/dev/null
```

07·16의 이론을 우리는 관찰로 재구성했습니다 — 이 문서들은 **저자들이 그것을 결정한 이유**를 말합니다. 두 관점이 만나면 이해가 완성됩니다.

## Step 7. 코드 투어 노트 (산출물)

```markdown
# vpc-cni 좌표 노트 (내 디버깅용)
| 증상/개념 | 파일:함수 | 모듈 |
|-----------|----------|------|
| warm pool 부족 판정 | pkg/ipamd/ipamd.go: isDatastorePoolTooLow | 07 |
| EC2 IP/prefix 추가 요청 | pkg/ipamd/ipamd.go: increaseDatastorePool → awsutils | 07·16 |
| "no available IP addresses" | pkg/ipamd/datastore: Assign… | 16 |
| veth 생성·netns 설정 | routed-eni-cni-plugin/driver/driver.go: SetupPodNetwork | 18 |
| /32 host route | 같은 파일의 netlink.Route | 18 |
| awscni_* 메트릭 | pkg/ipamd (prometheus 등록부) | 16 알람 |
| SNAT 규칙 | pkg/networkutils | 18 §3 |
```

## 정리

읽기 전용. lab-02에서 빌드·테스트·기여로.
