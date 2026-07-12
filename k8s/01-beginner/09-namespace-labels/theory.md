# 이론 — Namespace, Label/Selector, Annotation

> **🌱 17세 눈높이 비유**
> - **Namespace** = 학교의 "학년". 1학년에도 김민준, 2학년에도 김민준이 있을 수 있습니다(이름 충돌 해결). 학년별 규칙(쿼터)과 담임 권한(RBAC)도 따로. **하지만 복도(네트워크)는 공유라서 2학년 교실에 그냥 걸어갈 수 있습니다.**
> - **Label** = 명찰에 붙이는 스티커들 (`동아리=축구부`, `급식조=A`). "축구부 전원 모여"처럼 **무리를 지목**하는 용도.
> - **Annotation** = 가방에 붙은 견출지 메모 ("월수금 우유 안 먹음"). 지목용이 아니라 **참고 정보**.

---

## 1. Namespace

### 1.1 무엇을 위한 것인가

- 이름 범위: `default`의 `web`과 `staging`의 `web`은 별개
- 권한 경계: "이 팀은 자기 ns만" (RBAC, 모듈 11)
- 자원 한도: ns 단위 ResourceQuota/LimitRange
- 일괄 정리: ns 삭제 = 내부 리소스 전부 삭제 (조심!)

### 1.2 격리되지 않는 것 (시험 포인트)

- **네트워크**: ns가 달라도 `web.staging.svc.cluster.local`로 그냥 호출됩니다. 차단은 NetworkPolicy(모듈 15)
- **노드/커널**: 같은 노드를 공유 — 강한 격리는 별도 클러스터/vCluster(모듈 34)
- 클러스터 스코프 리소스: Node, PV, StorageClass, ClusterRole 등은 ns에 속하지 않습니다

```bash
kubectl api-resources --namespaced=false   # ns 없는 리소스 목록
```

### 1.3 기본 제공 ns

| ns | 용도 |
|----|------|
| default | 지정 안 했을 때 (실무에선 직접 만든 ns 사용 권장) |
| kube-system | K8s 시스템 컴포넌트 (건드리지 않기) |
| kube-public | 모두 읽기 가능 영역 (거의 안 씀) |
| kube-node-lease | 노드 하트비트 (Lease 객체) |

### 1.4 ResourceQuota / LimitRange

```yaml
apiVersion: v1
kind: ResourceQuota              # ns의 "총량" 한도
metadata: { name: team-quota, namespace: dev }
spec:
  hard:
    requests.cpu: "4"
    limits.memory: 8Gi
    pods: "20"
    services.loadbalancers: "0"   # LB 생성 금지 (비용 가드!)
---
apiVersion: v1
kind: LimitRange                 # 개별 Pod/컨테이너의 "기본값과 상하한"
metadata: { name: defaults, namespace: dev }
spec:
  limits:
  - type: Container
    default: { memory: 256Mi }          # limits 미지정 시 기본값
    defaultRequest: { cpu: 100m, memory: 128Mi }
    max: { memory: 2Gi }
```

> **💡 주의**: Quota가 걸린 ns에서는 requests/limits 없는 Pod 생성이 **거부**됩니다. LimitRange의 기본값이 이를 보완하는 짝꿍.

## 2. Label — 선택당하기 위한 메타데이터

### 2.1 문법

key=value. key는 선택적 prefix 가능(`app.kubernetes.io/name`). 값 63자 제한, 영숫자/`-_.`.

### 2.2 셀렉터 2형식

```bash
# 등호 기반
kubectl get pods -l app=web                  # 일치
kubectl get pods -l app!=web                 # 불일치
kubectl get pods -l app=web,tier=front       # AND

# 집합 기반 (강력!)
kubectl get pods -l 'env in (dev,staging)'
kubectl get pods -l 'env notin (prod)'
kubectl get pods -l 'release'                # key 존재
kubectl get pods -l '!release'               # key 부재
```

YAML에서는 `matchLabels`(등호)와 `matchExpressions`(집합)로 대응:

```yaml
selector:
  matchExpressions:
  - { key: env, operator: In, values: [dev, staging] }
```

### 2.3 표준 라벨 세트 (실무 관례)

```yaml
labels:
  app.kubernetes.io/name: order-api          # 앱 이름
  app.kubernetes.io/instance: order-api-prod # 설치 인스턴스
  app.kubernetes.io/version: "1.4.2"
  app.kubernetes.io/component: backend
  app.kubernetes.io/part-of: shop
  app.kubernetes.io/managed-by: helm
```

도구들(Helm, ArgoCD, 대시보드, 비용 분석)이 이 키들을 인식합니다. 우리 커리큘럼 실습은 간결성을 위해 `app: x`를 쓰지만, 운영 차트는 표준 세트로 (모듈 17 Helm에서 자동 생성).

## 3. Annotation — 메모장

```yaml
metadata:
  annotations:
    kubernetes.io/change-cause: "v1.4.2 결제 버그 수정"
    owner: "team-checkout@example.com"
    nginx.ingress.kubernetes.io/rewrite-target: /   # 컨트롤러 설정 (모듈 06의 그것)
```

- selector 불가, 값 크기 제한 느슨(총 256KiB) — 긴 JSON도 OK
- 시스템도 적극 사용: `kubectl rollout restart`의 restartedAt(모듈 04), kubectl의 last-applied-configuration
- Ingress annotation처럼 "컨트롤러에게 주는 설정 채널"로도 쓰임 — Gateway API가 이를 표준 필드로 옮긴 것이 모듈 06의 역사

## 요약 카드

| 질문 | 답 |
|------|----|
| ns가 격리하는 것? | 이름, RBAC 범위, 쿼터 (네트워크 ❌) |
| ns 없는 리소스 확인? | `kubectl api-resources --namespaced=false` |
| label의 존재 이유? | selector에게 **선택당하기** 위해 (K8s의 조인 키) |
| annotation과의 구분 기준? | "셀렉터로 찾을 일이 있는가" |
| Quota + 미지정 Pod? | 거부됨 — LimitRange 기본값으로 보완 |
