# 이론 — CNI 스펙, veth, VPC CNI vs 오버레이

> **🌱 17세 눈높이 비유: 신축 아파트의 인터넷 개통**
> 새 세대(Pod)가 입주하면 통신사 기사(CNI 플러그인)가 와서: **벽 안에 랜선(veth 페어)을 깔고** — 한쪽 끝은 집 안(Pod의 eth0), 다른 쪽 끝은 복도 배선반(노드) — **공유기에 IP를 등록**하고, **단지 배선도(라우팅 테이블)** 에 "이 IP는 이 집"이라고 적습니다.
> 기사를 부르는 건 관리사무소(kubelet)이고, 작업 지시서 양식(CNI 스펙)만 맞으면 어느 통신사(Calico, Cilium, VPC CNI)든 쓸 수 있습니다.
> 단지 간 통신은 두 방식: **EKS식** = 모든 집 IP가 시(VPC) 전체에서 유효한 진짜 주소 (추가 포장 불요). **오버레이식** = 단지끼리 택배 상자(VXLAN)에 넣어 배송.

---

## 1. CNI 스펙 — 작업 지시서

CNI는 놀랍도록 단순합니다: **"실행 파일을 호출하는 규약"** 입니다.

```
kubelet(정확히는 containerd) → /opt/cni/bin/<플러그인> 실행
  환경변수: CNI_COMMAND=ADD|DEL|CHECK, CNI_NETNS=/proc/<pid>/ns/net, CNI_IFNAME=eth0 ...
  stdin:    네트워크 설정 JSON (/etc/cni/net.d/*.conf)
  stdout:   결과 JSON (할당된 IP, 라우트, DNS)
```

- **ADD**: sandbox 생성 직후 (모듈 26 타임라인의 1단계) — IP 부여와 배선
- **DEL**: Pod 삭제 시 — 회수. **DEL 실패가 IP 누수의 근원** (pitfalls)
- 플러그인 **체인**: 설정 파일의 plugins 배열 순서대로 실행 — 메인(배선) 플러그인 뒤에 보조들이 이어집니다:

```json
{ "cniVersion": "1.0.0", "name": "aws-cni",
  "plugins": [
    { "type": "aws-cni", ... },          // 메인: IP 할당 + veth
    { "type": "egress-cni", ... },       // 보조: egress 처리
    { "type": "portmap", ... },          // 보조: hostPort 구현
    { "type": "bandwidth", ... }         // 보조: 대역폭 제한 annotation 구현
  ] }
```

## 2. veth 페어 — 양끝이 다른 세계에 있는 랜선

```
[Pod NET namespace]              [노드(호스트) namespace]
   eth0  ◀━━━━ veth 페어 ━━━━▶  enixxxxxxx (또는 vethxxxx)
   10.0.1.5                       (IP 없음 — 그냥 랜선 끝)
                                  + 라우팅: "10.0.1.5는 enixxxxxxx로"
```

- 한쪽에 넣은 패킷이 반대쪽으로 나오는 **가상 케이블.** 페어의 한 끝을 Pod namespace에 넣고 이름을 eth0으로 바꾼 것이 "Pod의 네트워크"의 전부
- 노드의 `ip route`에 Pod IP별 경로가 등록됩니다 — "이 노드 안에서 그 Pod 찾아가는 법"

## 3. 노드 간 통신 — 두 유파

### VPC 네이티브 (EKS VPC CNI)

```
Pod A (10.0.1.5, 노드1) → Pod B (10.0.2.8, 노드2)
패킷의 src/dst가 처음부터 진짜 VPC IP
→ 노드1을 나서면 그냥 VPC 라우팅이 노드2로 배달 (캡슐화 없음!)
```

- 구현: 노드의 **ENI**(탄력 네트워크 인터페이스)들에 secondary IP를 미리 받아두고(warm pool) Pod에 나눠줌
- 장점: 단순/고성능, VPC 보안그룹·Flow Logs 등 AWS 도구가 Pod IP를 그대로 인식
- 비용: **VPC IP를 Pod 수만큼 소모** — 서브넷 고갈 문제 (prefix delegation 등 해법은 eks 파트 16)
- 인스턴스 타입별 ENI/IP 한도가 곧 **노드당 최대 Pod 수**가 됩니다 (t3.medium = 17개의 비밀!)

### 오버레이 (Flannel VXLAN, Calico IPIP 등)

```
Pod A (192.168.x.x — 클러스터 내부 전용 대역) → Pod B
노드1이 패킷을 UDP(VXLAN)로 포장: [외부: 노드1IP→노드2IP | 내부: PodA→PodB]
→ 노드2가 개봉해 Pod B에 전달
```

- 장점: 하부 네트워크에 무관(IP 무한정), 온프레미스 표준
- 비용: 캡슐화 오버헤드, 외부 도구가 Pod IP를 못 봄

### eBPF 세대 (Cilium)

iptables/라우팅 테이블 대신 커널 eBPF 프로그램으로 배선/정책/LB까지 — 모듈 28과 cncf 파트 22에서.

## 4. 패킷 여정 종합 (Service 경유 풀코스)

```
Pod A에서 curl http://svc (172.20.x.x)
① DNS: CoreDNS가 ClusterIP 응답           (모듈 16)
② A의 eth0 → veth → 노드1 netfilter
③ DNAT: 172.20.x.x → 10.0.2.8 (Pod B)     (모듈 28 — kube-proxy 규칙)
④ 라우팅: VPC가 노드2로 배달                (이 모듈)
⑤ 노드2: ip route → veth → Pod B eth0
⑥ 응답은 conntrack이 역변환                 (모듈 28)
```

이 6단계에 지금까지의 네트워크 모듈이 전부 들어 있습니다 — 장애 시 어느 단계인지 자르는 것이 디버깅입니다.

## 5. 소스코드에서 확인하기

- CNI 스펙/라이브러리: https://github.com/containernetworking/cni — `SPEC.md`가 의외로 짧습니다 (직접 읽을 만함)
- 표준 플러그인들(bridge, portmap...): https://github.com/containernetworking/plugins — `plugins/main/bridge/bridge.go`의 veth 생성 코드
- AWS VPC CNI: https://github.com/aws/amazon-vpc-cni-k8s — `cmd/routed-eni-cni-plugin/`(플러그인), `pkg/ipamd/`(IP 풀 관리 데몬 — aws-node Pod의 본체)

## 요약 카드

| 질문 | 답 |
|------|----|
| CNI의 정체? | "실행 파일 호출 규약" — ADD/DEL + JSON |
| Pod의 eth0의 실체? | veth 페어의 한쪽 끝 (반대쪽은 노드에) |
| EKS Pod IP의 특별함? | 진짜 VPC IP — 캡슐화 없음, 대신 IP 소모 |
| 노드당 Pod 수 한도의 출처? | 인스턴스 타입별 ENI×IP 한도 (VPC CNI) |
| 오버레이의 트레이드오프? | IP 자유 ↔ 캡슐화 오버헤드/가시성 저하 |
| IP 누수의 근원? | CNI DEL 실패/누락 |
