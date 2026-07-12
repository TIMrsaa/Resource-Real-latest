# 이론 — 클러스터 아키텍처와 조정 루프

> **🌱 17세 눈높이 비유: K8s 클러스터는 "프랜차이즈 본사 + 지점들"입니다**
> - **API 서버** = 본사 콜센터 (모든 요청은 여기로만. 지점끼리 직접 연락 금지)
> - **etcd** = 본사 금고 (모든 계약서·장부의 유일한 원본)
> - **스케줄러** = 신규 매장 입지 선정 담당 ("이 가게는 강남점 자리가 좋겠군")
> - **컨트롤러 매니저** = 점검 순회 매니저들 ("계약서엔 가게 3개인데 2개뿐이네? 하나 더 열어")
> - **kubelet** = 각 지점장 (본사 지시대로 자기 지점에 가게를 차리고 상태 보고)
> - **kube-proxy** = 각 지점의 전화 교환원 (대표번호로 온 손님을 실제 가게로 연결)
>
> 포인트: **매니저들은 서로 대화하지 않습니다.** 전부 본사 콜센터(API 서버)를 통해서만 일합니다.

---

## 1. 전체 그림 (이 커리큘럼의 지도)

```
────────────────── CONTROL PLANE (EKS에서는 AWS가 관리) ──────────────────
                                                    ┌──────────┐
   kubectl ──────┐                                  │   etcd   │
   (사용자)       │                                  │ (상태 금고)│
                 ▼                                  └────▲─────┘
          ┌─────────────┐  저장/조회 (유일한 etcd 접근자)    │
          │  kube-      │◀──────────────────────────────┘
          │  apiserver  │◀──── watch/update ──── kube-scheduler
          │ (모든 것의   │◀──── watch/update ──── kube-controller-manager
          │  관문)      │                         (Deployment, Node, Job,
          └─────▲──────┘                          EndpointSlice... 컨트롤러 수십 개)
                │
─────────────── │ ───────── WORKER NODES (내 EC2) ────────────────────────
                │ watch/report
      ┌─────────┴──────────┐
      │      kubelet       │──▶ containerd ──▶ runc ──▶ 컨테이너들 (Pod)
      │  (노드의 Pod 책임자) │
      └────────────────────┘
      ┌────────────────────┐
      │     kube-proxy     │──▶ iptables/IPVS 규칙 (Service 라우팅)
      └────────────────────┘
      ┌────────────────────┐
      │     CNI 플러그인    │──▶ Pod에 IP 부여, 네트워크 연결
      └────────────────────┘
```

**철칙 3가지** (전부 시험에 나온다고 생각하세요):

1. **etcd에 쓸 수 있는 것은 API 서버뿐**입니다. 스케줄러도 kubelet도 etcd를 직접 못 봅니다.
2. **컴포넌트끼리 직접 통신하지 않습니다.** 전부 API 서버를 통한 watch(구독)와 update(보고)입니다.
3. **API 서버는 상태를 저장만 하고, 행동은 각 컨트롤러가 합니다.** API 서버가 똑똑한 게 아니라, 멍청한 게시판에 똑똑한 구독자들이 붙어 있는 구조입니다.

## 2. Control Plane 컴포넌트

### 2.1 kube-apiserver — 유일한 관문

- REST API 서버입니다. `kubectl get pods` = `GET /api/v1/namespaces/default/pods` HTTP 호출.
- 모든 요청에 대해: **인증(누구냐) → 인가(권한 있냐) → admission(규정에 맞냐) → 검증 → etcd 저장** 파이프라인을 수행 (고급 모듈 21에서 해부).
- **watch**: "이 리소스에 변화가 생기면 알려줘"라는 구독 메커니즘. K8s의 실시간성은 폴링이 아니라 watch로 구현됩니다.

### 2.2 etcd — 단일 진실 원본 (Single Source of Truth)

- Raft 합의 알고리즘 기반 분산 키-값 저장소. 모든 리소스가 `/registry/pods/default/my-pod` 같은 키로 저장됩니다.
- 클러스터의 "상태"는 오직 여기에만 있습니다. **etcd가 죽으면**: 이미 돌던 컨테이너는 계속 돌지만(kubelet은 마지막 지시 유지), 새 배포/변경/복구가 전부 멈춥니다 — 뇌사 상태.
- 백업 = etcd 스냅샷 (모듈 22, 36).

### 2.3 kube-scheduler — 입지 선정만 합니다

- 하는 일: `spec.nodeName`이 **빈** Pod를 watch → 최적 노드를 골라 `nodeName`을 **적어주기만** 합니다. 실행은 안 합니다!
- 2단계 결정: **Filtering**(자격 미달 노드 탈락: 자원 부족, taint 등) → **Scoring**(남은 후보 점수화: 분산 배치, 이미지 보유 여부 등).
- 실행은 그 노드의 kubelet이 watch로 알아채서 합니다. — 역할 분리의 교과서.

### 2.4 kube-controller-manager — 조정 루프 묶음

수십 개의 컨트롤러가 한 바이너리에 들어 있습니다. 각자 패턴은 동일:

```
for {
    현재 상태 = API서버에서 관찰 (watch)
    원하는 상태 = 리소스의 spec
    if 다르면 { 차이를 메꾸는 API 호출 }
}
```

| 컨트롤러 | 감시 대상 | 하는 일 |
|----------|----------|---------|
| Deployment | Deployment | ReplicaSet 생성/조정 (롤링업데이트 = RS 두 개의 비율 조절) |
| ReplicaSet | ReplicaSet | Pod 개수 맞추기 |
| Node | Node 하트비트 | 노드 응답 없으면 NotReady 마킹 → Pod 퇴거 |
| Job | Job | 완료까지 Pod 재시도 |
| EndpointSlice | Service/Pod | Service 뒤 Pod IP 목록 갱신 |

> **💡 status vs spec**: 모든 리소스는 `spec`(원하는 상태, 사용자가 씀)과 `status`(현재 상태, 컨트롤러가 씀)를 가집니다. K8s 전체가 "spec과 status의 차이를 0으로 만드는 기계"다.

### 2.5 cloud-controller-manager — 클라우드 연동

`type: LoadBalancer` Service를 만들면 실제 AWS NLB를 만들어주는 등, 클라우드 제공자별 로직 담당. EKS에서는 AWS가 관리합니다.

## 3. Node 컴포넌트

### 3.1 kubelet — 노드의 Pod 책임자

- "내 노드에 배정된 Pod 목록"을 watch → CRI(Container Runtime Interface)로 containerd에 컨테이너 생성 지시 → 상태를 API 서버에 보고.
- probe(건강검진) 실행, 리소스 관리, 볼륨 마운트도 kubelet 담당.
- **kubelet은 컨테이너를 직접 만들지 않습니다** — containerd에게 시킵니다 (모듈 01의 그림과 연결).

### 3.2 kube-proxy — Service의 구현체

- Service(가상 IP)로 온 트래픽을 실제 Pod IP로 보내는 **iptables/IPVS 규칙**을 노드마다 유지.
- 프록시 "서버"가 아닙니다 — 규칙을 설치하는 설치공이고, 실제 패킷 처리는 커널이 합니다 (모듈 28에서 해부).

### 3.3 컨테이너 런타임 + CNI

- containerd: 컨테이너 생성/관리 (모듈 01).
- CNI 플러그인: Pod가 만들어질 때 IP를 주고 네트워크에 연결 (EKS에서는 VPC CNI — eks 파트에서 심층).

## 4. 선언적 API — 왜 이 설계인가

명령형 시스템과 비교하면 설계 의도가 보입니다:

| | 명령형 (예: 스크립트로 직접 ssh) | 선언형 (K8s) |
|---|---|---|
| 장애 복구 | 사람이 알아채고 재실행 | 컨트롤러가 차이를 발견하고 자동 복구 |
| 중간 실패 | 어디까지 됐는지 알 수 없음 | 상태가 etcd에 있으니 이어서 조정 |
| 동시 변경 | 충돌 | API 서버가 직렬화 + 낙관적 잠금(resourceVersion) |
| 확장 | 스크립트 수정 | 새 컨트롤러만 추가 (CRD/Operator — 모듈 24, 30) |

> **🌱 비유**: 명령형은 "후진 3미터, 좌회전 30도..."를 외치는 주차 코치, 선언형은 "저 칸에 주차해줘"라고 말하면 되는 자율주차입니다. 도중에 고양이가 지나가도(장애) 자율주차는 알아서 다시 경로를 잡습니다.

## 5. EKS는 이 그림에서 무엇인가

```
┌── AWS가 소유/운영 (보이지 않음, $0.10/h) ──┐   ┌── 내가 소유 (EC2) ──┐
│  apiserver × N (멀티 AZ 자동 HA)           │   │  kubelet            │
│  etcd × N (자동 백업)                      │◀──│  kube-proxy         │
│  scheduler, controller-manager            │   │  VPC CNI            │
└────────────────────────────────────────────┘   └─────────────────────┘
```

- control plane 운영(HA 구성, etcd 백업, 버전 패치)을 AWS에 외주한 것이 EKS입니다.
- 우리는 API 서버의 **엔드포인트 URL**만 받습니다. `kubectl get nodes`를 쳐도 control plane 노드는 안 보입니다 — 우리 것이 아니니까.
- 그 대가로 control plane 내부 설정(예: API 서버 플래그) 자유도는 제한됩니다. 이 트레이드오프가 eks 파트의 출발점.

## 6. 소스코드에서 확인하기

- 컴포넌트별 진입점: https://github.com/kubernetes/kubernetes 의 `cmd/kube-apiserver`, `cmd/kube-scheduler`, `cmd/kube-controller-manager`, `cmd/kubelet`
- ReplicaSet 컨트롤러의 조정 루프 본체: `pkg/controller/replicaset/replica_set.go` 의 `syncReplicaSet` — 의외로 읽을 만합니다. "개수 세서 부족하면 만든다"가 코드로 그대로 있습니다.

## 요약 카드

| 질문 | 답 |
|------|----|
| K8s의 두뇌는? | 없습니다 — API 서버(게시판) + 독립 조정 루프들의 합주 |
| etcd에 접근 가능한 컴포넌트는? | kube-apiserver 단 하나 |
| 스케줄러가 하는 일은? | Pod에 노드 이름을 **적는 것**까지 (실행은 kubelet) |
| 컴포넌트 간 통신 방법은? | 전부 API 서버 경유 watch/update |
| EKS가 관리해주는 것은? | control plane 전부 (apiserver, etcd, scheduler, c-m) |
