# 이론 — 네트워킹 4+1층 전수 지도, eBPF 전환, Envoy 계보

> **🌱 17세 눈높이 비유: 도시의 우편 시스템**
> - **CNI** = 집집마다 주소와 우편함을 설치하는 공사팀 — Pod가 생길 때 IP와 배관(인터페이스)을 만듭니다
> - **CoreDNS** = 전화번호부 — "가게 이름"을 "주소"로 바꿔줍니다
> - **kube-proxy(iptables)** = 교차로마다 붙인 안내 쪽지 더미 — 쪽지가 수천 장이면 매번 다 뒤져야 합니다
> - **eBPF** = 교차로의 전자 안내판 — 쪽지 더미 대신 즉시 조회(해시맵). 게다가 안내판에 카메라(관찰)도 달 수 있습니다
> - **Envoy** = 만능 접수 창구 기계 — 어느 건물(인그레스·게이트웨이·메시)이든 이 기계를 넣고 "설정만" 다르게 내려줍니다
> - **메시** = 모든 가게 사이의 전용 보안 배송망 — 암호화·기록·우회로가 기본 장착 (eks 20)

---

## 1. 층 1 — CNI: Pod 네트워크의 시공사들

CNI는 명세입니다(컨테이너에 네트워크를 붙이는 플러그인 인터페이스) — 구현들이 경쟁합니다:

| 프로젝트 | 성숙도 | 방식 | 한 줄 |
|---|---|---|---|
| **Cilium** | Graduated | **eBPF** | CNI+kube-proxy 대체+정책+관찰(Hubble)+메시까지 — 이 층의 현재 중심 (심층 22) |
| **Calico** | (Tigera — 비CNCF) | 라우팅(BGP)/eBPF 모드 | NetworkPolicy의 오랜 표준격 — 오픈소스+상용 이원 |
| Flannel | (비CNCF급) | 오버레이(VXLAN) | 단순함의 대명사 — 정책 없음(Calico와 조합하던 역사) |
| Antrea | Sandbox급* | OVS | vSphere 세계와의 접점 |
| kube-router / kube-ovn 등 | Sandbox~ | 각기 | 변주들 |
| **vpc-cni** | (AWS — eks 16) | **네이티브 VPC IP** | 오버레이 없음 — Pod가 VPC 시민. IP 소진 방정식의 그 주인공 |

선택 축 세 가지: ① **오버레이 vs 네이티브 라우팅**(캡슐화 오버헤드 vs 인프라 통합 — vpc-cni는 후자의 극단) ② **NetworkPolicy 지원·표현력**(Flannel은 없음, Cilium은 L7 정책까지) ③ **kube-proxy 대체 여부**(eBPF 계열의 성능 이점). eks에서는 vpc-cni가 기본이되 Cilium을 얹는 조합(정책·관찰 목적)도 실무에 있습니다.

## 2. 층 2 — DNS·디스커버리

| 프로젝트 | 성숙도 | 한 줄 |
|---|---|---|
| **CoreDNS** | Graduated | K8s 기본 DNS — 플러그인 체인 아키텍처(Corefile). 심층 20 |
| etcd | Graduated | 디스커버리의 원천(모든 것의 저장소) — 09 지도·21 심층에서 |
| gRPC | Incubating | 서비스 간 RPC 표준 — HTTP/2 + 프로토버프, 로드밸런싱 함의(헤드리스 서비스) |

k8s에서 배운 것의 재확인: Service 디스커버리의 실체는 "CoreDNS가 Service 이름을 ClusterIP로" + "kube-proxy/eBPF가 ClusterIP를 실제 Pod로" — 두 층의 합작입니다.

## 3. 층 3 — 프록시·인그레스·게이트웨이: Envoy 계보도

```
                    ┌─ Istio (사이드카/ambient의 데이터플레인)      ← 메시 (eks 20, 심층 24)
Envoy (Graduated) ──┼─ Contour (Incubating — 인그레스 컨트롤러)
  L7 프록시 엔진     ├─ Emissary-ingress (Incubating — API 게이트웨이)
  동적 설정 = xDS    ├─ Envoy Gateway (Gateway API 구현체 — Envoy 프로젝트 직속)
                    └─ 수많은 상용 게이트웨이의 코어
비Envoy 계열: NGINX Ingress(레거시 대표), HAProxy, Traefik, Kong(자체+NGINX) — 대부분 비CNCF
```

- **Envoy가 공용 부품이 된 이유**: 설정을 파일이 아니라 **API(xDS)로 실시간 주입** — 컨트롤플레인들이 "설정 생성기"로 그 위에 앉을 수 있었습니다(02의 확장 지점 논리, 프록시판). 심층 23
- **Gateway API**(k8s 표준, Ingress의 후계 — 루트 버전표): 역할 분리(인프라팀 Gateway / 앱팀 HTTPRoute)와 표현력 — 구현체가 이 계보의 프로젝트들입니다. eks 14의 ALB도 자기 구현을 가짐

## 4. 층 4 — 서비스 메시 (eks 20의 지도 확장)

| 프로젝트 | 성숙도 | 데이터플레인 | 한 줄 |
|---|---|---|---|
| **Istio** | Graduated | Envoy 사이드카 / **ambient**(노드 프록시) | 기능 최대·복잡도 최대 — 심층 24 |
| **Linkerd** | Graduated | 자체 Rust 마이크로프록시 | 단순·경량 노선 — 심층 25 |
| Cilium Service Mesh | (Cilium 일부) | eBPF(+Envoy L7) | "사이드카 없는 메시"의 급진파 |
| Kuma | Sandbox급* | Envoy | Kong 계열 — 멀티존 지향 |

메시 선택의 실질은 48(비교 가이드)에서 — 지도 수준의 요점: **사이드카 유무와 데이터플레인이 무엇인가**가 계보를 가릅니다. eks 20에서 배운 mTLS STRICT·트래픽 관리가 이 층의 공통 기능.

## 5. 지각 변동 — eBPF vs iptables (구조로 이해하기)

```
iptables (전통):
  Service 1개 → NAT 규칙 여러 개 → 체인에 선형 추가
  Service 5,000개 → 규칙 수만 개 → 패킷마다 체인 순회 + 규칙 갱신 자체가 느려짐
eBPF (Cilium 등):
  커널에 검증된 프로그램 삽입 → Service→백엔드가 해시맵 조회 O(1)
  + 같은 지점에서 관찰(Hubble: 누가 누구에게, 어느 정책이 드롭했나)·정책·암호화까지
```

의미: 성능만이 아니라 **관찰과 정책이 데이터 경로 안으로** 들어왔습니다 — 별도 에이전트가 패킷을 복사해 보는 게 아니라, 지나가는 자리에서 봅니다. 이것이 Cilium이 CNI·관찰·메시를 한 몸에 담는 구조적 근거입니다(과대포장 경계는 pitfalls에서). eBPF 자체는 커널 기술이고 eBPF 재단(LF)이 따로 있습니다 — CNCF 지도의 경계 밖 뿌리(03의 runc·Kata와 같은 통찰).

## 6. 전수 보충 — 그 밖의 이름들

```
Network Service Mesh (Sandbox급) — L2/L3 수준의 "네트워크" 연결 메시 (통신사·NFV 계열)
Submariner — 클러스터 간 Pod 네트워크 연결 (멀티클러스터 L3 — 02의 Karmada와 이웃)
Kube-OVN / Antrea — OVS 계열 CNI
MetalLB — 베어메탈의 LoadBalancer 구현 (클라우드 LB가 없는 곳의 필수품)
ExternalDNS — Service/Ingress를 실제 DNS 레코드로 (Route53 등 — eks와 접점)
```

## 7. 소스/도구에서 확인하기

- CNI 명세: https://github.com/containernetworking/cni
- Cilium/eBPF: https://docs.cilium.io — `concepts/ebpf` / https://ebpf.io
- Envoy xDS: https://www.envoyproxy.io/docs — dynamic configuration
- Gateway API: https://gateway-api.sigs.k8s.io
- 성숙도 재확인: lab-01 (landscape.yml)

## 요약 카드

| 질문 | 답 |
|------|----|
| 지도의 층? | CNI / DNS·디스커버리 / 프록시·게이트웨이 / 메시 (+eBPF라는 지각 변동) |
| CNI 선택 축? | 오버레이 vs 네이티브, 정책 표현력, kube-proxy 대체(eBPF) — vpc-cni는 네이티브의 극단 |
| Envoy 계보? | Istio·Contour·Emissary·Envoy Gateway... — "설정 생성기"들이 xDS 위에 앉은 구조 |
| eBPF의 의미? | 체인 순회 → 해시맵 + 관찰·정책이 데이터 경로 안으로 — Cilium 한 몸 구조의 근거 |
| 메시 계보 기준? | 사이드카 유무 × 데이터플레인(Envoy/Rust/eBPF) — 상세 비교는 48 |
| 이 지도의 재단 경계? | eBPF(LF), Calico(Tigera), NGINX류 — CNCF 밖 구성원 상시 확인 (01) |
