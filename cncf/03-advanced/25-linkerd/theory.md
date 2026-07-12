# 이론 — 아키텍처, Rust 프록시, 자동 mTLS, 골든 메트릭, 선택 축

> **🌱 17세 눈높이 비유: 만능 스위스 army knife vs 잘 드는 과도**
> - **Istio(Envoy)** = 스위스 army knife — 20가지 도구가 다 달려 있습니다. 뭐든 되지만 무겁고, 어느 도구를 쓸지 배워야 합니다
> - **Linkerd(전용 프록시)** = 잘 드는 과도 하나 — 자르는 것만 합니다. 대신 가볍고, 꺼내자마자 바로 씁니다
> - **자동 mTLS** = 과도에 기본으로 달린 안전 장치 — 켜고 끄고 할 것 없이 항상 안전
> - **골든 메트릭** = 과도를 쓸 때마다 자동으로 남는 사용 기록 (몇 번 잘랐나, 얼마나 걸렸나, 실패했나)
> - **철학** = "부엌에서 90%는 과도로 충분합니다. 스테이크 칼이 필요한 순간에만 큰 칼을" — 22의 "L7은 필요한 곳에만"과 같은 정신

---

## 1. 아키텍처 — Istio와의 구조 대비

```
Linkerd:
  control plane (linkerd namespace):
    destination   서비스 디스커버리·정책을 프록시에 제공 (Istio의 istiod xDS와 유사 역할)
    identity      mTLS 인증서 발급 (Istio의 istiod CA와 유사)
    proxy-injector 사이드카 주입 webhook
  data plane:
    linkerd2-proxy (Rust 마이크로프록시) — Pod마다 사이드카

Istio(24)와의 대응:
  destination + identity + injector ≈ istiod의 세 역할
  차이: linkerd는 xDS(Envoy 프로토콜)가 아니라 자체 gRPC API로 프록시와 통신
        (전용 프록시라 Envoy xDS 호환이 필요 없습니다)
```

## 2. 왜 Rust 전용 프록시인가

| | Envoy (Istio) | linkerd2-proxy |
|---|---|---|
| 언어 | C++ | **Rust** (메모리 안전) |
| 범위 | 범용 프록시 | 사이드카 전용 |
| 크기 | 수십 MB (기능 많음) | **수 MB** (핵심만) |
| 설정 | xDS, 방대 | 최소 (거의 자동) |
| 확장 | WASM, 필터 | 제한적 |
| 프로토콜 | 광범위 | HTTP/1·2, gRPC, TCP (핵심) |

```
설계 논리:
  "메시 사이드카가 필요한 것"만 담습니다 → 작고, 안전하고, 빠르고, 설정 표면이 작습니다
  Rust → 메모리 안전(C++의 취약점 계열 제거), 예측 가능한 성능(GC 없음)
  대가: Envoy의 방대한 기능(ext_authz, WASM, 온갖 프로토콜)을 포기
       → "그 기능이 필요하면 Linkerd는 답이 아니다"
```

## 3. 자동 mTLS — 설정 없이 켜집니다

```
설치 → 사이드카 주입 → mTLS가 이미 켜져 있습니다 (PeerAuthentication 같은 CRD 불필요)

신원: ServiceAccount 기반 (identity가 SA별 인증서 발급)
  → Istio의 SPIFFE ID와 유사한 개념, 자동
동작: 두 linkerd2-proxy가 상호 TLS + 상호 인증
확인: linkerd viz edges — 어느 연결이 mTLS인지 (✓ 표시)

★ Istio: PERMISSIVE→STRICT 마이그레이션이 명시적
  Linkerd: 기본이 자동 mTLS(메시 안), 메시 밖과는 평문 (opaque ports 등으로 조정)
  → "설정 없이 안전"의 철학
```

## 4. 골든 메트릭 — 자동 관측

```
사이드카가 모든 트래픽을 보므로 자동 생성 (06의 격자, RED 메트릭):
  성공률(success rate): 2xx·3xx 비율
  RPS(초당 요청)
  지연(latency): p50/p95/p99

linkerd viz (관측 확장):
  linkerd viz stat deploy    → 각 워크로드의 골든 메트릭 (실시간)
  linkerd viz top            → 실시간 요청 top (13의 조사 동선과 유사)
  linkerd viz tap            → 실시간 요청 스트림 (개별 요청 관찰 — tcpdump-for-requests)
  linkerd viz edges          → 서비스 간 연결 + mTLS 상태

★ Prometheus 기반이되 카디널리티를 의도적으로 억제 (24의 폭발 문제를 설계로 회피)
```

## 5. 트래픽 기능 — 최소주의

```
있는 것:
  트래픽 분할: TrafficSplit (SMI) 또는 HTTPRoute (Gateway API) — 카나리(17)
  재시도·타임아웃: ServiceProfile 또는 HTTPRoute
  로드밸런싱: EWMA(지연 기반) 기본 — 느린 엔드포인트를 자동 회피

없는(또는 제한적인) 것:
  세밀한 헤더 조작, 외부 인가(ext_authz), WASM 확장, 복잡한 프로토콜
  → 이것이 필요하면 Istio(24) 또는 Gateway API + Envoy

★ Gateway API 채택: Linkerd도 표준(HTTPRoute)으로 수렴 중 (04의 Gateway API)
```

## 6. 선택의 축 — 48의 예고

```
축 하나: 기능의 최대치 vs 운영의 최소치

Istio를 고르는 경우:
  - 복잡한 트래픽 관리(세밀한 라우팅·미러링·외부 인가·WASM)
  - ambient로 대규모 비용 최적화
  - 이미 Envoy 생태계에 투자

Linkerd를 고르는 경우:
  - 원하는 것이 mTLS + 골든 메트릭 + 간단한 트래픽 분할
  - 운영 부담 최소화가 우선 (작은 팀, 메시 전담 인력 없음)
  - 예측 가능한 리소스(경량 사이드카)

Cilium 메시(22)를 고르는 경우:
  - 이미 Cilium CNI + 사이드카 없는 mTLS를 원함

★ "더 많은 기능"이 우월이 아닙니다 — 운영하지 않을 기능은 부채(24의 사고)
  안 쓸 기능의 복잡도를 지불하지 않는 것도 설계 결정
```

## 7. 소스/도구에서 확인하기

- Linkerd: https://linkerd.io/2/ — architecture, automatic-mtls, golden metrics
- linkerd2-proxy: https://github.com/linkerd/linkerd2-proxy (Rust)
- 왜 Rust인가: Linkerd 팀의 설계 문서·블로그
- 24(Istio)·48(선택 가이드)와 함께 읽기

## 요약 카드

| 질문 | 답 |
|------|----|
| 데이터플레인? | linkerd2-proxy — 자체 Rust 마이크로프록시(Envoy 아님, 계보도의 예외) |
| 왜 전용 프록시? | 사이드카에 필요한 것만 → 경량·안전·최소 설정 (기능 포기가 대가) |
| control plane? | destination(디스커버리) + identity(CA) + injector — istiod 세 역할과 유사 |
| 자동 mTLS? | 설치·주입만으로 켜짐, CRD 불필요 (SA 기반 신원) |
| 골든 메트릭? | 성공률·RPS·지연 자동, linkerd viz(stat/top/tap/edges) |
| 카디널리티? | 의도적 억제 — 24의 폭발 문제를 설계로 회피 |
| 트래픽 기능? | 최소주의 — 분할·재시도·타임아웃 O, WASM·ext_authz X |
| 선택 축? | 기능 최대(Istio) vs 운영 최소(Linkerd) — 둘 다 옳습니다 |
