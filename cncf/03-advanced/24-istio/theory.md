# 이론 — istiod, 트래픽 번역, mTLS·인가, ambient, 비용

> **🌱 17세 눈높이 비유: 통역사가 붙은 국제 회의**
> - **사이드카(Envoy)** = 각 참석자 옆에 붙은 개인 통역사 — 모든 대화를 통역·기록·검문
> - **istiod** = 통역 본부 — 회의 규칙(누가 누구와 말할 수 있나)을 각 통역사에게 실시간 무전(xDS)으로 지시하고, 참석자 신분증(mTLS 인증서)도 발급
> - **mTLS** = 두 통역사끼리 암호로 대화 + 서로 신분 확인 (참석자는 자기가 암호로 말하는 줄 모릅니다)
> - **VirtualService** = "A씨 발언은 B방으로 라우팅" 규칙 → 통역사에게 번역돼 전달
> - **ambient/ztunnel** = 개인 통역사 대신 **각 방(노드)에 공용 통역 부스** — 가볍습니다. 복잡한 통역(L7)이 필요한 방에만 전문 통역사(waypoint) 추가
> - **비용** = 통역사마다 인건비(메모리·CPU) + 통역 지연 — 그래서 "정말 통역이 필요한 회의인가"

---

## 1. istiod — 컨트롤플레인의 세 역할

```
istiod (단일 바이너리, 예전 Pilot+Citadel+Galley 통합)
├── ① xDS 서버: K8s + Istio CRD를 watch → Envoy 설정으로 번역 → 사이드카에 push
│      (23의 컨트롤플레인 = "K8s를 xDS로 번역"의 실체)
├── ② CA(인증서 기관): 각 워크로드에 SPIFFE ID 기반 인증서 발급 (mTLS용)
│      (19의 cert-manager와 유사하나 메시 전용 — SPIFFE는 33에서)
└── ③ 사이드카 주입: MutatingWebhook으로 Pod에 Envoy 컨테이너를 자동 삽입
       (namespace의 istio-injection=enabled 라벨 → 새 Pod에 사이드카)
```

```
데이터플레인:
  istio-proxy(Envoy) 사이드카 + init 컨테이너(iptables로 트래픽 가로채기)
  → Pod의 모든 인/아웃 트래픽이 사이드카를 경유 (앱은 모름)
  → 이 "투명한 가로채기"가 코드 수정 불필요의 비결
```

## 2. 트래픽 관리 — CRD가 Envoy 설정이 됩니다

| Istio CRD | Envoy 설정 | 역할 |
|---|---|---|
| **VirtualService** | route configuration (RDS) | 라우팅 규칙(경로·헤더·가중치·미러) |
| **DestinationRule** | cluster (CDS) | LB 정책·아웃라이어 감지·서브셋·mTLS 모드 |
| **Gateway** | listener (LDS) | 인그레스/이그레스 포트·TLS |
| **ServiceEntry** | cluster | 메시 밖 서비스를 메시에 등록 |
| Sidecar | listener 범위 축소 | 사이드카가 보는 서비스 제한(성능!) |

```yaml
# 카나리: 90/10 분할 (17의 Progressive Delivery가 이 위에)
apiVersion: networking.istio.io/v1
kind: VirtualService
spec:
  hosts: [reviews]
  http:
    - route:
        - { destination: { host: reviews, subset: v1 }, weight: 90 }
        - { destination: { host: reviews, subset: v2 }, weight: 10 }
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
spec:
  host: reviews
  subsets:
    - { name: v1, labels: { version: v1 } }
    - { name: v2, labels: { version: v2 } }
  trafficPolicy:
    outlierDetection: { consecutive5xxErrors: 5, interval: 30s }   # 23의 그 아웃라이어!
```

→ 이 CRD가 istiod에서 번역되어 사이드카의 route(가중치)와 cluster(서브셋·아웃라이어)로 나타납니다. **config_dump로 확인 가능**(23·lab-01).

## 3. 보안 — mTLS와 인가

### mTLS (서비스 간 자동 암호화·인증)

```yaml
apiVersion: security.istio.io/v1
kind: PeerAuthentication
metadata: { name: default, namespace: prod }
spec:
  mtls: { mode: STRICT }        # STRICT: mTLS만 / PERMISSIVE: 평문도 허용(마이그레이션)
```

```
동작:
  두 사이드카가 서로의 인증서(istiod CA 발급)로 TLS 핸드셰이크 + 상호 인증
  → 앱은 평문으로 말하지만 사이드카가 암호화 (투명)
  → 인증서에 SPIFFE ID(spiffe://cluster.local/ns/prod/sa/web) — 워크로드 신원(33)

마이그레이션: PERMISSIVE(평문+mTLS 모두 수용) → 전체 사이드카 배포 확인 → STRICT
  ★ 처음부터 STRICT면 사이드카 없는 워크로드와의 통신이 끊깁니다 (07의 audit→enforce 순서)
```

### 인가 (AuthorizationPolicy)

```yaml
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
spec:
  selector: { matchLabels: { app: api } }
  action: ALLOW
  rules:
    - from: [{ source: { principals: ["cluster.local/ns/prod/sa/frontend"] } }]  # SPIFFE ID로!
      to: [{ operation: { methods: ["GET"], paths: ["/api/*"] } }]
```

```
집행 지점: 사이드카 Envoy의 ext_authz/rbac 필터 (23의 필터 체인)
  → "누가(SPIFFE 신원) 무엇을(메서드·경로)" — L7 인가
  → 22의 Cilium L7 정책과 같은 문제, 다른 구현 (48에서 비교)
```

## 4. ambient 모드 — 사이드카를 없애입니다

```
[사이드카 모델 — 전통]
  Pod마다 Envoy 컨테이너 → 메모리·CPU 오버헤드 × Pod 수
  Pod 시작 시 사이드카도 시작(지연), 업그레이드 시 전 Pod 재시작

[ambient 모드]
  ztunnel (DaemonSet, 노드당 1):  L4 — mTLS·L4 인증. Rust로 작성, 가볍습니다
  waypoint (선택적 Deployment):    L7 — 라우팅·L7 인가. 네임스페이스/서비스 단위
  → mTLS만 원하면 ztunnel만 (사이드카 없음, 오버헤드 최소)
  → L7 기능 필요한 곳에만 waypoint 배포

계층:
  기본:      앱 → ztunnel(mTLS) → ztunnel → 앱    (L4, 초경량)
  L7 필요:   앱 → ztunnel → waypoint(L7 정책) → ztunnel → 앱
```

```
왜 중요한가:
  ① 비용: 대부분 워크로드가 L4 mTLS만 필요 → 사이드카 오버헤드 제거
  ② 운영: 사이드카 업그레이드의 전 Pod 재시작 지옥 완화
  ③ 22의 원칙("L7은 필요한 곳에만")을 아키텍처에 새김
대가:
  ① 상대적으로 새로움 (성숙도·엣지 케이스 — 채택 전 확인)
  ② 트래픽 경로가 달라짐 (디버깅 모델 변화)
  ③ ztunnel이 노드 단위 → 노드 프록시의 장애 반경
```

## 5. 관측 — 사이드카가 모든 것을 봅니다

```
자동 생성 (06의 격자에 편입):
  메트릭: istio_requests_total{source, destination, response_code} (RED 메트릭)
  트레이스: 사이드카가 span 생성 + x-request-id 전파 (12 — 단 컨텍스트 전파는 앱 책임!)
  액세스 로그: 요청별 상세

Kiali: 메시 토폴로지 시각화 (서비스 그래프 — 13의 SPM과 같은 아이디어)
★ 카디널리티 주의(11·23): source×destination×code = 시계열 폭발 가능
```

## 6. 비용 — 정직한 목록

```
① 사이드카 오버헤드(전통): Pod마다 Envoy 메모리(수십 MB)·CPU·지연(홉 추가)
② 복잡도: CRD 여럿(VirtualService/DestinationRule/PeerAuth/AuthzPolicy...) 상호작용
③ 장애 표면: istiod·사이드카·CA가 새 장애 지점 (mTLS 인증서 만료 = 통신 두절!)
④ 디버깅: config_dump·istioctl proxy-config 학습 (23의 그 기술)
⑤ 업그레이드: 데이터플레인·컨트롤플레인 버전 스큐, 카나리 업그레이드
⑥ 리소스: istiod 자체도 규모에 따라 스케일 (수천 사이드카 = 큰 xDS 부하)

판단: mTLS·트래픽관리·관측 중 몇 개가 실제 요구인가요?
  1개면 더 가벼운 수단, 3개 겹치고 운영 역량 있으면 메시
  (ambient가 이 저울을 메시 쪽으로 조금 옮겼습니다)
```

## 7. 소스/도구에서 확인하기

- Istio: https://istio.io/latest/docs — traffic-management, security, ambient
- istioctl: `istioctl proxy-config {route,cluster,endpoint,listener} <pod>` (config_dump 요약)
- ambient: https://istio.io/latest/docs/ambient/
- 23(Envoy)·33(SPIFFE)·48(선택 가이드)와 연결

## 요약 카드

| 질문 | 답 |
|------|----|
| istiod 세 역할? | xDS 서버(설정 번역) + CA(인증서) + 사이드카 주입 webhook |
| 마법의 실체? | 23의 Envoy 기능 + 그것을 자동 설정하는 번역기(istiod) |
| CRD → Envoy? | VirtualService→route, DestinationRule→cluster, Gateway→listener |
| mTLS 마이그레이션? | PERMISSIVE → 전체 배포 확인 → STRICT (audit→enforce, 07) |
| 인가 집행? | 사이드카의 rbac 필터, SPIFFE 신원으로 (L7 — 22와 같은 문제) |
| ambient? | ztunnel(L4 mTLS, 노드당) + waypoint(L7, 선택) — 사이드카 제거 |
| ambient의 원칙? | "L7은 필요한 곳에만"(22)을 아키텍처에 |
| 메시의 비용? | 사이드카 오버헤드·복잡도·장애표면·디버깅·업그레이드 — 요구 3개 겹칠 때 |
