# 이론 — Service, EndpointSlice, kube-proxy

> **🌱 17세 눈높이 비유: Service는 "치킨집 대표번호"다**
> 치킨집 배달 기사(Pod)는 매일 바뀝니다. 그만두기도 하고(크래시) 새로 오기도 합니다(스케일아웃). 손님이 기사 개인 번호(Pod IP)를 저장해두면 금방 결번이 됩니다.
> 그래서 가게는 **대표번호(ClusterIP)** 하나를 만들고, 사무실 전화 시스템(kube-proxy가 깐 규칙)이 "지금 일하는 기사 중 한 명"에게 자동으로 돌려줍니다.
> 기사 명단(EndpointSlice)은 실시간 갱신됩니다 — 단, **"지금 배달 가능"(Ready) 상태인 기사만** 명단에 올라갑니다.

---

## 1. 문제 정의: Pod IP는 쓸 수 없는 주소입니다

- Pod가 재생성되면 IP가 바뀝니다 (모듈 04에서 본 자가 치유 = IP 교체)
- 복제본이 3개면 어느 IP로? 부하는 어떻게 나누고?

Service는 이 두 문제를 "**고정 가상 IP + 자동 갱신되는 백엔드 목록**"으로 풉니다.

## 2. 연결 사슬의 3요소

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector:
    app: web          # ① 이 라벨의 Pod들이 백엔드
  ports:
  - port: 80          # ② Service가 받는 포트
    targetPort: 8080  # ③ Pod 컨테이너의 실제 포트
```

### 2.1 EndpointSlice — 실시간 백엔드 명단

EndpointSlice 컨트롤러가 selector에 맞고 **Ready인** Pod IP 목록을 유지합니다:

```bash
kubectl get endpointslices -l kubernetes.io/service-name=web
# → web-abc12   IPv4   8080   10.0.1.5,10.0.2.7,10.0.3.9
```

> **💡 readiness probe와의 결합**: probe에 실패한 Pod는 살아 있어도 **명단에서 빠집니다**. "배포/장애 중 트래픽이 안전한 Pod로만 가는" 메커니즘의 전부가 이것입니다. 옛 자료의 `Endpoints` 리소스는 EndpointSlice로 세대교체됐습니다 (대규모에서 갱신 효율 때문).

### 2.2 kube-proxy — 규칙 설치공

각 노드의 kube-proxy가 EndpointSlice를 watch하면서 커널에 규칙을 설치합니다:

```
"ClusterIP 172.20.x.x:80 으로 가는 패킷은
 → 10.0.1.5:8080, 10.0.2.7:8080, 10.0.3.9:8080 중 하나로 DNAT(주소 바꿔치기)"
```

- 모드: iptables(기본) / IPVS / nftables(1.33 GA). EKS 기본은 iptables.
- **패킷은 kube-proxy 프로세스를 통과하지 않습니다.** 커널이 규칙대로 처리합니다. (그래서 Service는 "홉"이 아닙니다 — 고급 모듈 28)

### 2.3 DNS — 이름으로 부르기

Service를 만들면 CoreDNS에 A 레코드가 생깁니다:

```
web                          # 같은 네임스페이스에서
web.default                  # 다른 네임스페이스에서
web.default.svc.cluster.local  # 풀네임 (FQDN)
```

코드에는 IP가 아니라 **이름**을 씁니다. (동작 원리는 모듈 16)

## 3. Service 4종

### 3.1 ClusterIP (기본) — 클러스터 내부 전용

- 가상 IP 부여 (EKS 기본 대역 172.20.0.0/16 등). **클러스터 밖에서는 접근 불가.**
- 용도: 마이크로서비스 간 내부 통신 (전체 Service의 90%)

### 3.2 NodePort — 모든 노드에 구멍 뚫기

- ClusterIP + **모든 노드의 고정 포트(기본 30000~32767)** 에서 수신
- `노드IP:30080` → 어느 노드로 들어가도 → 백엔드 Pod (다른 노드의 Pod로도 전달)
- 용도: 직접 쓰는 일은 드물고, LoadBalancer의 부품 또는 임시 테스트

### 3.3 LoadBalancer — 클라우드 LB 연결

- NodePort + **클라우드의 실제 로드밸런서** 자동 생성
- EKS: 컨트롤러가 NLB를 만들어 노드들(또는 Pod 직접)에 연결. 외부 DNS 주소 발급
- Service당 LB 1개 = **비용 1개** — HTTP 여러 서비스라면 Ingress/Gateway(모듈 06)로 LB 하나를 공유하는 것이 정석

### 3.4 ExternalName — 외부로 보내는 별명

- 백엔드가 Pod가 아니라 **DNS CNAME**: `db.example.com` 같은 외부 주소의 별명
- 용도: 외부 DB를 클러스터 내부 이름으로 추상화 (나중에 내부로 이전해도 코드 무수정)

### + Headless Service (`clusterIP: None`)

- 가상 IP 없이 DNS가 **Pod IP들을 직접** 반환. StatefulSet(모듈 19)에서 "개별 멤버 지명"용.

## 4. 트래픽 분배에 대한 진실

- 기본 분배는 **무작위**(iptables 확률 매칭)입니다. 라운드로빈이 아닙니다.
- L4(TCP) 분배입니다 — HTTP 요청 단위가 아니라 **커넥션 단위**. keep-alive 커넥션을 오래 물고 있으면 분배가 안 바뀝니다 (gRPC에서 유명한 문제 — 해결은 메시/L7, cncf 파트).
- 같은 클라이언트를 같은 Pod로 고정하려면: `sessionAffinity: ClientIP`.

## 5. 소스코드에서 확인하기

- kube-proxy iptables 규칙 생성부: `pkg/proxy/iptables/proxier.go` 의 `syncProxyRules` — "EndpointSlice 읽어서 iptables 체인 쓰기"가 그대로 있습니다
- EndpointSlice 컨트롤러: `pkg/controller/endpointslice/`

## 요약 카드

| 질문 | 답 |
|------|----|
| Service의 실체? | 각 노드 커널의 DNAT 규칙 (프록시 서버 아님) |
| ClusterIP에 ping이 안 가는 이유? | NIC에 없는 가상 IP니까 (정상) |
| 백엔드 명단 관리자? | EndpointSlice 컨트롤러 (Ready Pod만 등재) |
| 4종 포함 관계? | LB ⊃ NodePort ⊃ ClusterIP (+ExternalName은 별개) |
| HTTP 경로 라우팅? | Service 일이 아님 → Ingress/Gateway API |
