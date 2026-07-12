# 이론 — L7 라우팅: Ingress(과거)에서 Gateway API(현재)로

> **🌱 17세 눈높이 비유: 대형 쇼핑몰의 안내데스크**
> Service(모듈 05)는 각 매장의 직통 전화입니다. 그런데 손님은 쇼핑몰 정문(LB 하나)으로 들어와서 "신발 매장이요", "푸드코트요"라고 묻습니다.
> **안내데스크(Ingress/Gateway)** 가 목적지 말(호스트명/URL 경로)을 듣고 해당 매장(Service)으로 보내줍니다.
> - 안내데스크 **규정집** = Ingress/HTTPRoute 리소스 (YAML)
> - 규정집대로 일할 **직원** = Ingress Controller / Gateway 구현체 (nginx, envoy...) — **직원은 따로 고용해야 합니다!**

---

## 1. 왜 L7인가 — Service의 한계

| | Service (L4) | Ingress/Gateway (L7) |
|---|---|---|
| 보는 것 | IP/포트 | HTTP 호스트, 경로, 헤더, 메서드 |
| 라우팅 | 커넥션을 Pod로 | "shop.com/cart → cart-svc" |
| TLS | 통과만 | **종료(termination)** — 인증서를 여기서 관리 |
| LB 비용 | 서비스당 1개 | **여러 서비스가 1개 공유** |

## 2. Ingress — 구세대 표준 (읽을 줄 알아야 함)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
  annotations:                                    # ← 문제의 그곳
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx                         # 어느 컨트롤러가 처리할지
  rules:
  - host: shop.example.com
    http:
      paths:
      - path: /cart
        pathType: Prefix
        backend:
          service:
            name: cart
            port: { number: 80 }
```

### Ingress의 구조적 문제 (Gateway API 탄생 배경)

1. **표현력 부족**: 표준 스펙에는 호스트/경로 매칭뿐. 가중치 분배, 헤더 매칭, 리다이렉트... 전부 없음
2. **annotation 지옥**: 부족한 기능을 구현체별 annotation으로 — `nginx.ingress.kubernetes.io/...` 수십 개. **다른 컨트롤러로 갈아타면 전부 무효** (이식성 붕괴)
3. **역할 미분리**: 한 리소스에 인프라 설정(TLS, LB)과 앱 라우팅이 섞임 — 누가 소유? 권한 경계는?

> 그래서 Ingress는 기능 동결(유지보수 모드)됐고, 신규 표준이 Gateway API입니다.

## 3. Gateway API — 현세대 표준

핵심 설계: **역할별로 리소스를 쪼갰습니다.**

```
GatewayClass        "어떤 구현체인가"          ← 구현체 벤더 제공 (nginx, istio, ...)
   └─ Gateway       "LB를 이렇게 떠라"         ← 인프라/플랫폼팀 소유
        └─ HTTPRoute "내 앱 라우팅 규칙"        ← 개발팀 소유 (네임스페이스별)
        └─ GRPCRoute / TLSRoute / TCPRoute ...  ← HTTP 외 프로토콜도 표준
```

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gw
spec:
  gatewayClassName: nginx
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces: { from: All }      # 어느 네임스페이스의 Route를 붙여줄지 (권한 경계!)
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: shop-route
spec:
  parentRefs:
  - name: main-gw                    # 어느 Gateway에 붙는지
  hostnames: ["shop.example.com"]
  rules:
  - matches:
    - path: { type: PathPrefix, value: /cart }
      headers:                        # 헤더 매칭 — 표준 필드!
      - name: x-beta-user
        value: "true"
    backendRefs:
    - name: cart-v2
      port: 80
      weight: 10                      # 가중치 분배 — 표준 필드! (카나리)
    - name: cart-v1
      port: 80
      weight: 90
```

### Ingress 대비 무엇이 좋아졌나

| 요구사항 | Ingress | Gateway API |
|----------|---------|-------------|
| 카나리 (90:10) | 구현체별 annotation | `weight` 표준 필드 |
| 헤더 기반 라우팅 | annotation 또는 불가 | `matches.headers` 표준 |
| 리다이렉트/재작성/미러링 | annotation | `filters` 표준 |
| gRPC/TCP/TLS 라우팅 | 불가 | GRPCRoute/TCPRoute/TLSRoute |
| 팀 간 권한 분리 | 없음 | Gateway(인프라) / Route(개발) + allowedRoutes |
| 컨트롤러 교체 | annotation 전면 재작성 | 표준 필드라 대부분 그대로 |

> **💡 멘탈모델**: Ingress가 "구두 계약 + 회사마다 다른 부록"이라면, Gateway API는 "표준 계약서 + 역할별 서명란"입니다.

## 4. 구현체 생태계 (2026 기준)

| 구현체 | 기반 | 특징 |
|--------|------|------|
| NGINX Gateway Fabric | nginx | 학습/범용 (이 모듈에서 사용) |
| Envoy Gateway | envoy | CNCF, Envoy 생태계 표준 |
| Istio | envoy | 메시 겸용 |
| Cilium | eBPF | CNI 겸용 |
| AWS (VPC Lattice / ALB) | AWS 관리형 | eks 파트에서 |

같은 HTTPRoute YAML이 어느 구현체에서나 돕니다 — 이것이 표준화의 가치.

## 5. 트래픽 경로 전체 그림

```
인터넷 → NLB/ALB → Gateway 구현체 Pod (nginx/envoy)  ← L7 규칙 적용 (HTTPRoute)
                        → 백엔드 Pod로 직접 (EndpointSlice 참조)
```

구현체 Pod 자체는 보통 LoadBalancer Service로 노출됩니다 — 모듈 05의 지식 위에 정확히 한 층을 얹은 것.

## 6. 소스코드에서 확인하기

- Gateway API 스펙 (CRD로 배포됨): https://github.com/kubernetes-sigs/gateway-api — `apis/v1/httproute_types.go` 에서 위 YAML 필드들의 정의를 그대로 볼 수 있습니다
- 스펙 문서: https://gateway-api.sigs.k8s.io/ — conformance 테스트로 구현체 호환성을 강제하는 구조도 흥미롭습니다

## 요약 카드

| 질문 | 답 |
|------|----|
| Ingress 리소스만 만들면? | 아무 일도 없음 — 컨트롤러(실행체)가 따로 필요 |
| Gateway API 3계층? | GatewayClass(구현체) / Gateway(LB, 인프라팀) / HTTPRoute(라우팅, 개발팀) |
| Ingress의 한계 3가지? | 표현력 부족, annotation 비표준, 역할 미분리 |
| 카나리 배포의 표준 필드? | HTTPRoute `backendRefs[].weight` |
| TLS는 어디서 끝나나요? | Gateway listener (인증서는 Secret 참조) |
