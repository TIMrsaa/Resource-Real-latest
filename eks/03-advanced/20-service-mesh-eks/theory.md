# 이론 — sidecar의 세계: 구조, mTLS, 트래픽 문법

> **🌱 17세 눈높이 비유: 부서마다 배치된 전담 비서**
> 큰 회사(클러스터)의 부서(서비스)들이 서로 전화(호출)를 합니다:
> - **sidecar(Envoy)** = 부서마다 앉은 전담 비서 — 모든 전화를 대신 받고 대신 겁니다. 직원(앱)은 "옆자리 비서에게 말할 뿐"
> - **istiod** = 비서실장 — 모든 비서에게 규칙("영업팀 전화의 10%는 신입 팀으로", "3번 재시도")과 **신분증(인증서)** 을 배포합니다
> - **mTLS** = 비서끼리 통화 전 서로 사원증 제시 — 도청도, 사칭도 차단. 직원은 그런 절차가 있는지도 모릅니다
> - **fault 주입** = 비서실장이 훈련 삼아 "영업팀 전화 절반을 2초 늦게 연결해봐" — 부서(코드)는 결백한 채 장애 리허설
> - **ambient** = 부서마다 비서를 두는 대신 **층마다 공용 데스크** — 인건비(리소스)를 줄인 신형 배치
> - 그리고 비용: 비서들 월급(Pod당 메모리), 비서실 규정 학습(운영 복잡도) — 공짜가 아닙니다

---

## 1. 남북과 동서 — 14와의 관할 분담

```
남북(north-south): 유저 → ALB → 서비스        ← 14의 손잡이들
동서(east-west):   서비스 A → B → C → D        ← 메시의 관할
```

동서에서 반복되는 요구: 암호화+신원(mTLS), 재시도/타임아웃/서킷, 배포 시 트래픽 분할, 호출 관계의 골든 메트릭·트레이스. 언어별 라이브러리로 N번 구현하는 대신 — **프록시를 옆에 세워 네트워크 계층에서 한 번에** 푸는 것이 메시의 제안입니다.

## 2. Istio 구조 — 두 평면

```
Control Plane: istiod
  ├ 설정 배포: VirtualService 등 CRD → Envoy 설정(xDS)으로 번역·푸시
  ├ 인증서: SA 기반 SPIFFE 신원 발급·자동 회전 (mTLS의 심장)
  └ sidecar 주입: mutating webhook (k8s 23의 그 메커니즘!) —
      ns 라벨(istio-injection=enabled) 보고 Pod 생성 시 Envoy 컨테이너를 끼워 넣음

Data Plane: Pod마다 Envoy sidecar
  └ iptables로 Pod의 in/out 트래픽을 전부 가로채 프록시 경유시킴
     (EKS+PSA restricted 환경에선 init의 NET_ADMIN 대신 istio-cni가 이 일을 대행)
```

**ambient 모드**(신형): sidecar 없이 — 노드 단위 ztunnel(L4: mTLS·신원)과 필요한 곳만 waypoint 프록시(L7)로 분리. Pod당 오버헤드가 사라지는 대신 성숙도·기능 커버리지를 확인하고 채택. 이 모듈의 실습은 이해가 쉬운 sidecar 모드로 합니다.

## 3. mTLS — 신원 기반 보안, NetworkPolicy와의 분업

- 신원: 인증서의 주체가 IP가 아니라 **ServiceAccount 기반 SPIFFE ID**(`spiffe://cluster/ns/shop/sa/web`) — Pod가 옮겨 다녀도(IP가 바뀌어도) 신원 불변
- 모드: `PERMISSIVE`(mTLS도 평문도 수용 — 이행기) → `STRICT`(mTLS만 — 메시 밖 평문 거부). **PERMISSIVE로 깔고 STRICT로 조이는** 2단계가 무중단 도입의 정석
- NetworkPolicy(15·18)와의 관계 — 계층이 다릅니다:

| | NetworkPolicy | mTLS(PeerAuthentication) |
|---|---|---|
| 층 | L3/4 (IP/포트) | L4 위의 신원+암호화 |
| 질문 | "이 주소가 접근 가능한가" | "**누구인지 증명**했는가 + 도청 불가" |
| 집행 | eBPF(노드) | Envoy(Pod 옆) |

둘은 대체가 아니라 **겹층 방어**입니다 — NP로 대역을 좁히고 mTLS로 신원을 강제.

## 4. 트래픽 문법 — CRD 두 장이 대부분을 말합니다

```yaml
# DestinationRule — "목적지의 분류와 정책"
subsets: [{ name: v1, labels: { version: v1 } }, { name: v2, labels: { version: v2 } }]
trafficPolicy:
  outlierDetection:              # 서킷브레이커 — 연속 5xx 내는 인스턴스를 잠시 퇴출
    consecutive5xxErrors: 5
    baseEjectionTime: 30s
---
# VirtualService — "라우팅 규칙"
http:
- route:
  - { destination: { host: podinfo, subset: v1 }, weight: 90 }
  - { destination: { host: podinfo, subset: v2 }, weight: 10 }   # 카나리아
  retries: { attempts: 3, perTryTimeout: 2s }
  fault: { delay: { percentage: { value: 50 }, fixedDelay: 2s } }  # 카오스 리허설
```

- 카나리아 분할이 **replicas 수와 무관**합니다 — 14의 ALB 가중치는 남북에서, 이건 동서 어디서나
- retry의 양날: 폭풍(retry storm) 위험 — 하류가 아픈데 3배 트래픽을 얹는 꼴. perTryTimeout·서킷과 반드시 세트
- fault 주입 = 코드 무수정 카오스 엔지니어링 — "타임아웃 설정이 진짜 동작하나"를 프로덕션 전에

## 5. EKS 위의 메시 — 배선 특이사항

- **유입 접합**: ① ALB → istio ingressgateway(NLB/ALB 뒤) → 메시 — L7 제어 일원화 ② ALB → Pod 직행(14 그대로) + 메시는 내부만 — 단순. 선택 기준은 "남북에도 메시 문법이 필요한가"
- **VPC CNI 궁합**: 오버레이가 없으므로(18) sidecar 가로채기는 Pod 안 iptables만의 일 — CNI와 충돌 없음. PSA restricted ns라면 istio-cni 플러그인으로 NET_ADMIN 요구 제거(32)
- **Fargate/Auto Mode**: DaemonSet 불가 환경(06) — sidecar 모드는 되고, ambient(ztunnel=DS)는 불가
- **VPC Lattice**: AWS의 새 방향 — 클러스터·VPC·계정을 넘는 서비스 네트워킹을 관리형으로. 메시의 대체라기보다 "크로스 경계 연결"에 특화 — App Mesh 유민의 한 목적지

## 6. 관측 보너스 — 공짜처럼 보이는 것

sidecar가 모든 호출을 지나므로 골든 메트릭(요청수/오류율/지연 — 서비스 쌍 단위)과 트레이스 전파가 자동으로 나옵니다(Prometheus/Grafana/Kiali·Tempo와 연동 — cncf 파트). 단 "공짜"가 아니라 **이미 지불한 sidecar 비용의 배당**입니다.

## 7. 소스/도구에서 확인하기

- Istio: https://github.com/istio/istio — `pilot/`(istiod의 xDS 번역부)
- Envoy: https://github.com/envoyproxy/envoy — 메시의 실제 데이터 플레인
- App Mesh EOL 공지와 마이그레이션 가이드 (관리형 락인 사례 연구로 읽기)
- VPC Lattice: AWS 문서 — "Amazon VPC Lattice"

## 요약 카드

| 질문 | 답 |
|------|----|
| 메시의 관할? | 동서(서비스 간) 트래픽의 L7 제어 — 남북은 14 |
| 두 평면? | istiod(규칙·인증서 배포) + Envoy sidecar(가로채는 프록시) |
| 주입 메커니즘? | mutating webhook + ns 라벨 (k8s 23) |
| mTLS 신원의 단위? | ServiceAccount 기반 SPIFFE ID — IP가 아닙니다 |
| 도입 순서? | PERMISSIVE → 검증 → STRICT (무중단 2단계) |
| retry의 안전벨트? | perTryTimeout + outlierDetection(서킷) — 폭풍 방지 |
| 메시를 사지 말아야 할 때? | 서비스 적고 한 팀 — ALB+NP+라이브러리로 충분 |
