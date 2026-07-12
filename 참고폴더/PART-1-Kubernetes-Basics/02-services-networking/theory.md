# 이론 — Service & Networking

> **🌱 Service = 회사 대표 전화번호**
> 직원 (Pod) 은 자주 바뀌고 자리도 옮긴다. 손님 (Client) 이 직원 개인 휴대폰 번호를 외워두면 그 직원이 퇴사하는 순간 끊긴다.
> 대표 번호 (Service) 하나만 알면 안내데스크가 알아서 현재 자리에 있는 직원 (Endpoints) 에게 연결해준다.

## 1. 왜 Service가 필요한가

Pod의 IP는 **짧은 수명**입니다. Pod가 재시작되면 IP가 바뀝니다. Pod에 직접 IP로 접속하는 건 깨지기 쉽습니다.

**Service 가 하는 일**:
1. **고정된 가상 IP** (ClusterIP) 제공
2. 라벨 셀렉터로 묶인 Pod들에게 **부하 분산**
3. **DNS 이름** 부여 (예: `my-svc.default.svc.cluster.local`)

```
Client (Pod) ──→ Service (ClusterIP 10.100.5.7)
                         │
                         ├──→ Pod-A (10.0.1.5)
                         ├──→ Pod-B (10.0.2.6)   ← Endpoints
                         └──→ Pod-C (10.0.3.7)
```

`Endpoints` 는 Service의 셀렉터에 매칭되는 Pod의 IP 목록입니다. Service를 만들면 자동으로 같이 만들어집니다.

> **🧠 "Service 가 안 통하면 Endpoints 부터 봐라"**
> Service 가 생성됐는데 트래픽이 안 가는 99% 원인은 *Endpoints 비어 있음* (selector 가 라벨과 안 맞거나 Pod 가 Ready 가 아님).
> `kubectl get endpoints <svc>` 한 줄이면 selector 문제인지 Pod 자체 문제인지 즉시 갈린다.

---

## 2. Service 타입 4가지

### 2.1 ClusterIP (기본값)

- 클러스터 내부에서만 접근 가능한 가상 IP
- 외부 노출은 별도 (Ingress, port-forward, NodePort/LB)
- **거의 모든 Service의 기본**

```yaml
spec:
  type: ClusterIP    # 생략해도 동일
  selector:
    app: web
  ports:
    - port: 80           # Service 노출 포트
      targetPort: 8080   # Pod 컨테이너 포트
```

### 2.2 NodePort

- 모든 노드의 특정 포트(30000~32767)를 열어서 외부에서 노드 IP:포트로 접속 가능
- 단순하지만 운영에서 직접 쓰는 경우는 적음 (LB가 더 깔끔)
- 학습/디버깅용으로 유용

```yaml
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30080    # 생략하면 자동 할당
```

### 2.3 LoadBalancer

- 클라우드 공급자가 LB를 자동 프로비저닝 (AWS면 NLB)
- ClusterIP + NodePort 를 포함하면서, 그 위에 외부 LB 추가
- 인터넷 노출이 가장 단순한 방법
- **주의: 비용 발생** (시간당 약 0.0225 USD + 데이터)

```yaml
spec:
  type: LoadBalancer
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 8080
```

EKS에서는 기본적으로 **CLB(Classic LB)** 가 만들어지지만, AWS Load Balancer Controller가 설치되어 있으면 어노테이션으로 NLB/ALB로 변경 가능 (Part 2에서 다룸).

### 2.4 ExternalName

- 클러스터 내 DNS에 외부 도메인을 CNAME으로 등록
- 예: `db.example.com` 을 `db` 라는 짧은 이름으로 호출 가능
- 거의 안 씀

```yaml
spec:
  type: ExternalName
  externalName: api.external.com
```

> **🧠 Service "타입" 은 4개지만 진짜 쓰는 건 사실상 2개**
> 운영에선 ClusterIP (내부) + LoadBalancer/Ingress (외부) 가 99%.
> NodePort 는 학습/디버그용, ExternalName 은 레거시 정도다. 처음엔 ClusterIP 만 깊게 익히면 충분.

---

## 3. 어떤 타입을 언제 쓰나

| 시나리오 | 타입 |
|---------|------|
| 내부 마이크로서비스 간 통신 | ClusterIP |
| 외부 인터넷 노출 (간단) | LoadBalancer |
| 외부 인터넷 노출 (HTTP 라우팅 + TLS + 다중 도메인) | Ingress (뒤단은 ClusterIP) |
| 노드 IP로 빠르게 접근 (개발/디버그) | NodePort |
| 외부 시스템을 짧은 이름으로 | ExternalName |

**Best Practice**: 외부 노출이 필요한 모든 HTTP 트래픽은 **Ingress + ClusterIP** 조합. LoadBalancer Service는 비-HTTP (gRPC/TCP) 또는 단순 케이스에만.

> **🧠 LB Service 를 남발하면 청구서가 폭발한다**
> Service 마다 `type: LoadBalancer` 로 만들면 *서비스 개수만큼 ALB/NLB 가 생성* 된다 — 한 달 수십~수백 달러 누수.
> Ingress 하나로 여러 ClusterIP 를 묶는 게 비용 + 관리 양쪽 모두 정답.

---

## 4. CoreDNS — 클러스터 DNS

K8s 클러스터 안에서는 CoreDNS Pod가 떠 있습니다 (`kube-system` NS).

### 4.1 자동 생성되는 DNS 레코드

Service `my-svc` 를 NS `prod` 에 만들면:
- `my-svc.prod.svc.cluster.local` → ClusterIP A 레코드
- 같은 NS의 Pod에서는 짧게: `my-svc`
- 다른 NS의 Pod에서는: `my-svc.prod`

Pod 단위 DNS도 있지만 거의 안 씁니다 (StatefulSet의 Headless Service 케이스 정도).

### 4.2 검색 도메인

Pod의 `/etc/resolv.conf` 는 자동으로:
```
search <ns>.svc.cluster.local svc.cluster.local cluster.local
nameserver <CoreDNS의 ClusterIP>
```

→ `curl my-svc` 만 해도 search 도메인이 차례로 붙어가며 시도.

> **🧠 search 가 양날의 검**
> 짧은 이름이 편하지만 *오타* 가 나도 search 도메인이 무한 시도하느라 latency 가 늘어난다 (특히 외부 DNS 호출).
> 외부 도메인은 끝에 `.` 을 붙여 FQDN 으로 (`example.com.`) — search 가 무시되어 1회만 조회.

---

## 5. kube-proxy — 뒤에서 하는 일

ClusterIP는 **실제로 존재하지 않는 IP** 입니다. Pod가 ClusterIP로 패킷을 보내면 무엇이 그 패킷을 실제 Pod로 라우팅할까요?

→ **kube-proxy** (DaemonSet) 가 각 노드의 iptables/ipvs 룰을 관리해 패킷을 변환합니다.

```
Pod-X → 10.100.5.7 (ClusterIP)
   ↓
[노드의 iptables DNAT 룰]
   ↓
Pod-A (10.0.1.5) 또는 Pod-B 또는 Pod-C 중 임의로 라운드로빈
```

**EKS에서는 모드가 `iptables` 가 기본**. 대규모 클러스터(수천 Service)면 `ipvs` 모드가 효율적이지만 학습 단계에서는 무관.

> **EKS 1.35 (현재 최신)**: Cilium 같은 eBPF 기반 솔루션을 쓰면 kube-proxy를 대체 가능 (advanced).

> **🧠 "라운드로빈" 은 iptables 의 거짓말**
> iptables 의 분배는 *진짜 라운드로빈이 아니라 통계적 확률* (probability) 기반이다 — 짧은 시간엔 한 Pod 에 트래픽이 쏠릴 수 있음.
> 그래서 connection 수가 낮은 환경에선 분배가 균일해 보이지 않는 게 정상이다.

---

## 6. Ingress — HTTP 라우팅 레이어

### 6.1 Ingress vs Service

- **Service**: L4 (TCP/UDP). LB Service는 노드 IP로 트래픽을 받는 단순 분배.
- **Ingress**: L7 (HTTP/HTTPS). 호스트 이름, 경로 기반 라우팅 + TLS 종료.

### 6.2 Ingress 자체는 "설정"

Ingress 리소스는 **명세만** 합니다. 실제 트래픽 처리는 **Ingress Controller** 가 합니다.

K8s 표준에는 Ingress Controller가 없습니다. 별도 설치:
- **AWS Load Balancer Controller** (EKS) — Ingress를 ALB로 매핑
- nginx-ingress, traefik, contour, ...

### 6.3 예시

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
spec:
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api-svc
                port: { number: 80 }
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web-svc
                port: { number: 80 }
```

→ `https://app.example.com/api/*` 는 `api-svc` 로, 나머지는 `web-svc` 로.

> **본 모듈에서는** Ingress Controller 설치까지는 안 갑니다. Part 2의 06-vpc-cni-networking 에서 AWS LB Controller 설치하고 본격 사용.

> **🧠 Ingress 리소스는 "설계도", Controller 가 "건설사"**
> Ingress YAML 만 만든다고 ALB 가 뜨지 않는다 — Controller 가 그 설계도를 보고 실제 LB 를 만든다.
> 그래서 "Ingress 만들었는데 ALB 안 생긴다" 하면 Controller 가 설치/권한이 있는지부터 확인.

---

## 7. 핵심 정리

```
[외부] → ALB (Ingress Controller가 만듦)
           │ (L7 라우팅)
           ▼
       Service (ClusterIP)  ← 안정된 내부 주소
           │ (kube-proxy DNAT)
           ▼
        Pod-A / Pod-B / Pod-C  ← 셀렉터로 묶인 Endpoints
           │ (CoreDNS로 이름 해석)
           ▼
       다른 Service / Pod
```

> **🧠 한 줄 요약: "이름 → 가상 IP → 실제 Pod"**
> CoreDNS 가 이름을, kube-proxy 가 가상 IP 를, Endpoints 가 실제 Pod 목록을 책임진다.
> 트래픽이 안 갈 때 이 3단계 중 어디서 끊겼는지만 찾으면 모든 네트워킹 디버깅이 풀린다.

다음: [lab-01-clusterip.md](./lab-01-clusterip.md)

---

## 부록 A — Service 4종 한 장 비교

| 타입 | 어디서 접근 가능? | 외부 IP? | 비용 | 언제? |
|------|-----------------|---------|------|------|
| **ClusterIP** | 클러스터 내부만 | ❌ | 무료 | 마이크로서비스 간 통신 (대다수 케이스) |
| **NodePort** | 노드 IP:30000~32767 | 노드 IP | 무료 | 학습/디버깅 |
| **LoadBalancer** | 외부 인터넷 | LB DNS | NLB ~$0.022/시 | 단순 외부 노출 |
| **ExternalName** | DNS CNAME | ❌ | 무료 | 외부 시스템에 짧은 이름 부여 |

## 부록 B — 트래픽이 흐르는 길 (한장 그림)

```
[외부 사용자]
     │
     │  https://app.example.com/api
     ▼
[ALB] (Ingress Controller가 자동 생성)
     │  호스트/경로 매칭으로 분기
     ▼
[Ingress 리소스] — "이 경로는 api-svc로!"
     │
     ▼
[Service: ClusterIP 10.100.5.7]
     │  kube-proxy iptables DNAT
     │  (랜덤하게 endpoint 중 하나 선택)
     ▼
[Pod-A 10.0.1.5]   [Pod-B 10.0.2.6]   [Pod-C 10.0.3.7]
     ↑               ↑                  ↑
     └───── selector(app=api) 로 묶인 endpoints ──────┘
```

## 부록 C — DNS 검색 도메인 실전 예시

Pod이 `default` NS에 있을 때:

```bash
curl http://web                              # ✅ default/web 으로 해석됨
curl http://web.default                      # ✅ 동일
curl http://web.default.svc.cluster.local    # ✅ FQDN (가장 명확)

# Pod이 monitoring NS에서 default/web을 호출하려면:
curl http://web.default                      # ✅ 다른 NS 호출엔 NS 명시 필요
curl http://web                              # ❌ monitoring/web을 찾음 (없으면 실패)
```

## 부록 D — FAQ

### Q1. "Service의 IP가 ping이 안 되는데 정상인가요?"
**정상**. ClusterIP는 가상 IP라 실제 인터페이스가 없습니다. ICMP(ping) 응답 안 하지만 TCP/UDP는 정상 라우팅됩니다.

### Q2. "Pod끼리 통신할 때 Service 안 거치고 Pod IP로 직접 호출하면 안 되나요?"
기술적으로 가능하지만 **하지 마세요**. Pod 재시작되면 IP 바뀝니다. Service가 추상화 계층의 핵심.

### Q3. "Headless Service는 언제 쓰나요?"
StatefulSet의 각 Pod에 직접 접근해야 할 때 (예: Redis 클러스터에서 redis-0은 primary, redis-1은 replica). `clusterIP: None` 으로 만들면 Service가 부하분산 안 하고 Pod별 DNS만 만들어줍니다.

### Q4. "LoadBalancer Service가 EXTERNAL-IP에 `<pending>`만 뜹니다"
- 클라우드 환경이 아닐 때 (로컬 minikube/kind) 정상. minikube면 `minikube tunnel` 실행
- AWS인데 안 뜨면: 노드의 IAM 권한, 서브넷 태그 (kubernetes.io/role/elb=1), VPC 설정 확인
