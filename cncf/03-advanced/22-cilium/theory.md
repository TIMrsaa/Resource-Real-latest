# 이론 — eBPF 실행 모델, Cilium 데이터 경로, identity, 정책, Hubble, 대가

> **🌱 17세 눈높이 비유: 고속도로 톨게이트 개조**
> - **iptables** = 톨게이트마다 규칙 종이 수천 장을 쌓아두고, 차가 올 때마다 위에서부터 한 장씩 읽습니다 — 규칙이 늘수록 느려집니다
> - **eBPF** = 톨게이트에 **작은 컴퓨터**를 설치. 번호판을 조회(해시맵)하면 즉시 답이 나옵니다. 게다가 그 컴퓨터에 카메라(관찰)·차단기(정책)·암호화 장치도 달 수 있습니다
> - **검증기(verifier)** = 그 컴퓨터에 프로그램을 넣기 전에 "무한 루프 없는지, 남의 메모리 안 건드리는지"를 심사 — 통과 못 하면 아예 설치 불가 (커널이 안 죽는 이유)
> - **identity** = 번호판(IP) 대신 **차종 코드**로 관리 — 차량이 바뀌어도 "택시는 택시"
> - **Hubble** = 톨게이트 컴퓨터가 남기는 통행 기록 — "왜 막았는지"까지 함께 (판정 지점 = 기록 지점)

---

## 1. eBPF 실행 모델

```
유저스페이스 (cilium-agent)
   │ ① 프로그램(바이트코드) 로드
   ▼
┌──────────── 커널 ────────────┐
│ 검증기(verifier)              │  ← 정적 분석: 루프 제한, 메모리 안전, 종료 보장
│   통과 → JIT 컴파일 → 기계어  │
│                               │
│ 훅 지점에 attach:             │
│   XDP     (NIC 드라이버 직후 — 가장 빠름, DDoS 차단)
│   tc(traffic control) ingress/egress  ← Cilium의 주 무대
│   socket, cgroup, kprobe, tracepoint ...
│                               │
│ eBPF 맵 (커널↔유저 공유)      │  ← 해시맵/배열/LRU: identity, service, conntrack, policy
└───────────────────────────────┘
```

**맵이 핵심입니다**: 프로그램은 작고 단순하게 유지하고, 상태(어떤 IP가 어떤 identity인지, 어떤 Service가 어떤 백엔드인지)는 맵에 둡니다. cilium-agent가 K8s를 watch해 맵을 갱신하고, 커널의 프로그램은 맵을 조회할 뿐입니다.

## 2. Cilium의 데이터 경로

```
Pod ──veth──▶ [tc ingress: bpf_lxc] ──▶ 라우팅/터널 ──▶ [tc: bpf_host] ──▶ NIC
                    │                                        │
                    ├ endpoint 정책 맵 조회 (허용/거부)        ├ 암호화(WireGuard)
                    ├ service 맵 조회 (ClusterIP → 백엔드)     └ 이벤트 → Hubble
                    └ conntrack 맵 (연결 추적)

주요 맵:
  cilium_lxc          엔드포인트(Pod) 정보
  cilium_ipcache      IP → identity 매핑 (클러스터 전역)
  cilium_lb4_services / cilium_lb4_backends   Service → 백엔드 (kube-proxy 대체)
  cilium_policy_<id>  엔드포인트별 정책 결정 맵
  cilium_ct4_global   conntrack
```

### 라우팅 모드

```
터널(VXLAN/Geneve): 노드 간 캡슐화 — 하부 네트워크와 무관, 오버헤드 있음
네이티브 라우팅:    Pod CIDR을 하부 네트워크가 라우팅 — 오버헤드 없음, 인프라 협조 필요
ENI/AWS 모드:      Pod가 VPC IP (eks 16의 vpc-cni와 같은 자리)
```

## 3. identity — IP를 버리입니다

```
Pod 라벨 {app=web, env=prod, ns=shop}
  → cilium-agent가 "보안 관련 라벨"만 추려 해시 → identity 번호(예: 12345)
  → 같은 라벨 집합의 모든 Pod가 같은 identity (노드·IP와 무관)

특수 identity:
  1  host       (노드 자신)
  2  world      (클러스터 밖 전부)
  4  health     (상태 점검)
  5  init       (identity 결정 전)
  6  remote-node
  reserved:kube-apiserver 등

정책 집행:
  패킷 도착 → 출발지 IP로 ipcache 조회 → identity
           → policy 맵에서 (src identity, dst port, proto) 조회 → 허용/거부
★ 규칙 수가 Pod 수가 아니라 라벨 조합 수에 비례 → 확장성
★ Pod 재생성(IP 변경)에도 정책이 그대로 유효
```

## 4. 정책 — L3/L4/L7과 CRD

```yaml
# 표준 NetworkPolicy는 L3/L4까지
# CiliumNetworkPolicy는 L7까지
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: { name: api-policy }
spec:
  endpointSelector: { matchLabels: { app: api } }
  ingress:
    - fromEndpoints: [{ matchLabels: { app: frontend } }]
      toPorts:
        - ports: [{ port: "8080", protocol: TCP }]
          rules:
            http:                       # ★ L7: HTTP 메서드·경로 단위
              - { method: "GET", path: "/api/v1/.*" }
  egress:
    - toFQDNs: [{ matchName: "api.stripe.com" }]   # ★ DNS 기반 egress (20과 결합)
    - toEntities: [kube-apiserver]
```

```
L7 정책의 대가: Envoy 프록시가 개입합니다(사이드카가 아닌 노드 프록시)
  → L3/L4는 순수 eBPF(빠름), L7은 Envoy 경유(지연·자원)
  → "L7 정책이 필요한 곳에만" 적용하세요

toFQDNs: DNS 응답을 가로채(20의 CoreDNS 아래) IP를 identity에 매핑
  → "stripe.com만 허용" 같은 정책이 가능. 단 DNS 프록시가 개입
```

## 5. kube-proxy 대체

```
kube-proxy(iptables): Service마다 NAT 규칙 체인 → 패킷마다 순회
Cilium eBPF:          cilium_lb4_services 맵 조회 O(1) + 백엔드 선택

kubeProxyReplacement=true 일 때 추가로:
  - socket-level LB: Pod 안에서 connect() 시점에 목적지를 바로 백엔드로 (홉 감소)
  - Maglev/Random 백엔드 선택 알고리즘
  - DSR(Direct Server Return), XDP 가속 옵션
  - NodePort/HostPort/ExternalIP도 eBPF로

★ 이점: 규칙 수와 무관한 성능, conntrack 부하 감소(20의 5초 지연 완화와 연결)
★ 요구: 커널 버전(4.19.57+, 기능별로 5.x 필요), 일부 기능은 특정 배포판 제약
```

## 6. Hubble — 판정 지점의 관찰

```
데이터 경로의 eBPF 프로그램이 이벤트를 링버퍼로 → hubble(agent) → hubble-relay → UI/CLI

hubble observe --verdict DROPPED --last 20
  → "누가 누구에게, 어느 정책이, 왜 떨궜는지" (정책 ID와 함께)

메트릭: hubble_drop_total, hubble_flows_processed_total, ...
서비스 맵: 플로우에서 서비스 간 의존 그래프 파생 (13의 SPM과 같은 아이디어)
```

**04에서 강조한 것**: 별도 에이전트가 패킷을 복사해 추측하는 것이 아니라, **판정하는 자리에서 판정 근거와 함께** 기록합니다. eks 18의 VPC Flow Logs가 답 못 하던 "왜 막혔나"에 답합니다.

## 7. 대가 — 정직한 목록

```
① 커널 요구: 기능별로 커널 버전 요구가 다릅니다. 관리형 K8s의 노드 이미지 확인 필수
② 디버깅 난이도: iptables -L 대신 cilium-dbg bpf ... / hubble observe (도구 학습 필요)
③ 통합 리스크: CNI+LB+정책+관찰이 한 컴포넌트 → 그것이 죽으면 여러 층이 동시에
④ 상호작용: 기존 iptables 기반 도구(일부 CNI 플러그인, 보안 에이전트)와 충돌 가능
⑤ L7 정책 비용: Envoy 경유 — 순수 eBPF의 성능 이점이 사라집니다
⑥ 업그레이드: 데이터 경로 교체 = 노드 롤링. 정책·맵 마이그레이션 검증 필요
★ "eBPF니까 도입"이 아니라 증상(Service 수천 개, 정책·관찰 통합 요구)이 근거여야
```

## 8. 소스/도구에서 확인하기

- Cilium: https://docs.cilium.io — concepts/ebpf, security/policy, kubeproxy-free
- eBPF: https://ebpf.io / https://docs.cilium.io/en/stable/bpf/
- Hubble: https://docs.cilium.io/en/stable/observability/hubble/
- cilium-dbg(구 cilium CLI in-pod): `cilium-dbg bpf lb list`, `cilium-dbg endpoint list`

## 요약 카드

| 질문 | 답 |
|------|----|
| eBPF의 안전성? | 검증기가 로드 전 정적 분석(루프·메모리·종료) → 커널이 안 죽습니다 |
| 상태는 어디에? | eBPF **맵** — agent가 갱신, 커널 프로그램은 조회만 |
| identity란? | 라벨 집합의 해시 ID — IP가 아니라 identity로 정책 (Pod 재생성에 무관) |
| 규칙 수의 스케일? | Pod 수가 아니라 **라벨 조합 수**에 비례 |
| kube-proxy 대체? | Service 맵 O(1) + socket LB — 규칙 수와 무관한 성능 |
| L7 정책의 대가? | Envoy 경유 — 필요한 곳에만 |
| Hubble의 차별점? | 판정 지점에서 판정 근거와 함께 기록 (추측이 아닙니다) |
| 정직한 대가? | 커널 요구·디버깅 난이도·통합 리스크·L7 비용·업그레이드 |
