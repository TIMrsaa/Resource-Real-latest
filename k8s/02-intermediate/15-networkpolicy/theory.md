# 이론 — NetworkPolicy 모델과 문법

> **🌱 17세 눈높이 비유: 아파트 단지의 출입 관리**
> 기본 상태의 K8s는 **모든 현관문이 열린 아파트**입니다 — 누구나 어느 집(Pod)이든 들어갑니다(모듈 09에서 확인).
> NetworkPolicy는 경비 시스템 도입입니다. 특이한 점: **어떤 집이 경비 명단에 오르는 순간, 그 집은 "명단에 적힌 손님 외 전부 차단"이 됩니다.** "수상한 사람 차단" 같은 블랙리스트는 아예 없고, 화이트리스트만 있습니다.
> 그리고 경비(CNI)를 **고용하지 않으면** 명단(정책)을 아무리 써 붙여도 아무도 막지 않습니다.

---

## 1. 동작 모델

```
Pod가 어떤 정책의 podSelector에도 안 걸림  → 그 Pod는 전부 허용 (기본)
Pod가 정책에 선택됨 (Ingress 방향)        → 허용 규칙 합집합 외 ingress 거부
Pod가 정책에 선택됨 (Egress 방향)         → 허용 규칙 합집합 외 egress 거부
```

- 정책은 ns 스코프 리소스 — podSelector는 **자기 ns의 Pod**만 선택합니다
- 여러 정책 = 허용의 **합집합**. 정책끼리 충돌 개념이 없습니다 (deny가 없으니)
- 연결 추적(stateful): ingress를 허용하면 그 연결의 **응답 패킷은 자동 허용** — 왕복을 따로 열 필요 없습니다

## 2. 문법 해부

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-policy
  namespace: shop
spec:
  podSelector:                  # ① 누구에게 적용? (빈 {} = ns의 모든 Pod)
    matchLabels: { app: api }
  policyTypes: [Ingress, Egress]  # ② 어느 방향을 "통제 모드"로 전환?
  ingress:
  - from:                       # ③ 허용 출처 (한 from 항목 안은 OR)
    - podSelector:              #    같은 ns의 frontend Pod
        matchLabels: { app: frontend }
    - namespaceSelector:        #    또는 monitoring ns의 모든 Pod
        matchLabels: { kubernetes.io/metadata.name: monitoring }
    ports:
    - { protocol: TCP, port: 8080 }
  egress:
  - to:
    - podSelector: { matchLabels: { app: db } }
    ports: [{ protocol: TCP, port: 5432 }]
  - to:                          # DNS 허용 (egress 정책의 필수 동반자!)
    - namespaceSelector: {}
      podSelector: { matchLabels: { k8s-app: kube-dns } }
    ports:
    - { protocol: UDP, port: 53 }
    - { protocol: TCP, port: 53 }
```

### 미묘하지만 결정적인 문법 2개

```yaml
# (a) 두 셀렉터가 "한 항목 안에" — AND: "monitoring ns의 prometheus Pod"
- namespaceSelector: { matchLabels: { team: monitoring } }
  podSelector: { matchLabels: { app: prometheus } }

# (b) 두 셀렉터가 "별개 항목" (각각 - 로 시작) — OR: "monitoring ns 전체 + 아무 ns의 prometheus"
- namespaceSelector: { matchLabels: { team: monitoring } }
- podSelector: { matchLabels: { app: prometheus } }
```

`-` 하나 차이로 의미가 완전히 달라집니다. 정책 리뷰에서 가장 자주 잡히는 버그.

> **💡 ns를 이름으로 지목**: 모든 ns에는 `kubernetes.io/metadata.name: <이름>` 라벨이 자동으로 붙습니다 — namespaceSelector에서 이름 매칭할 때 이걸 씁니다.

### ipBlock — 클러스터 밖 주소

```yaml
- to:
  - ipBlock:
      cidr: 10.100.0.0/16
      except: [10.100.5.0/24]
```

외부 DB, 온프레미스 대역 등. Pod IP에 쓰는 것은 부적합(IP가 바뀌니까) — Pod는 셀렉터로.

## 3. 표준 정책 세트 (복사해 쓰는 4장)

```yaml
# ① 기본 거부 (ingress) — 모든 ns에 까는 출발점
kind: NetworkPolicy
metadata: { name: default-deny-ingress }
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
# ② 같은 ns 안은 허용 (점진 도입 시 완충)
metadata: { name: allow-same-namespace }
spec:
  podSelector: {}
  ingress: [{ from: [{ podSelector: {} }] }]
---
# ③ DNS egress 허용 (egress 통제 시 필수)
#    (위 본문 예시의 kube-dns 조각)
---
# ④ 모니터링 ns에서 메트릭 수집 허용 (Prometheus 대비)
```

## 4. 집행자(CNI) 이야기

| CNI | NetworkPolicy |
|-----|---------------|
| VPC CNI (EKS 기본) | 지원 — 단, **애드온 설정으로 활성화 필요** (eBPF 기반 Network Policy Agent) |
| Calico | 지원 + 자체 확장(전역 정책, deny 등) |
| Cilium | 지원 + CiliumNetworkPolicy(L7: HTTP 메서드/경로까지!) — cncf 파트 22 |

표준 NetworkPolicy는 L3/L4(IP/포트)까지입니다. "GET은 되고 POST는 막기" 같은 L7은 Cilium/메시의 영역.

## 5. 소스코드에서 확인하기

- API 타입 정의: `staging/src/k8s.io/api/networking/v1/types.go` — AND/OR 의미가 주석으로 명시되어 있습니다
- VPC CNI의 정책 에이전트: https://github.com/aws/aws-network-policy-agent — eBPF로 구현

## 요약 카드

| 질문 | 답 |
|------|----|
| deny 규칙은? | 없음 — 선택되는 순간 기본 거부 + 허용 합집합 |
| 전체 기본 거부 한 장? | `podSelector: {}` + `policyTypes: [Ingress]` |
| 응답 패킷도 열어야? | 아니오 — stateful (연결 추적) |
| AND vs OR 구분? | 한 from 항목 안(AND) vs 별개 항목(OR) — `-` 위치 |
| egress 통제의 필수 동반? | kube-dns로의 53/UDP,TCP 허용 |
| 정책이 안 먹는 1순위 원인? | CNI가 집행 안 함 (EKS: 정책 기능 비활성) |
