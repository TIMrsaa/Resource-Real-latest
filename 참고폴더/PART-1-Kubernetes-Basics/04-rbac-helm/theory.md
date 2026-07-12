# 이론 — RBAC & Helm

> **🌱 RBAC = 회사 출입증, Helm = 이케아 조립 키트**
> RBAC: 누구 (SA) 가 어느 방 (Resource) 의 무엇을 (Verb) 할 수 있는지 출입증 룰을 정함.
> Helm: 가구 (앱) 를 매번 도면 그려서 만드는 대신, 공장 키트 (Chart) 와 옵션지 (values.yaml) 만 주면 똑같이 조립됨.

## 1. RBAC 핵심 4객체

```
ServiceAccount  ──[bound by]──→  RoleBinding  ──[ref]──→  Role
   (누가)                                                    (무엇을 할 수 있는가)

ServiceAccount  ──[bound by]──→  ClusterRoleBinding  ──→  ClusterRole
   (cluster-scope)                                          (cluster-scope)
```

### 1.1 ServiceAccount (SA) — "누구"

- Pod에 자동 첨부 (`spec.serviceAccountName` 미지정 시 `default` SA 사용)
- 자체 토큰을 가지고 K8s API 호출 시 인증
- IRSA(Part 2)에서는 AWS IAM Role과 매핑

### 1.2 Role / ClusterRole — "무엇을"

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: default
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
```

- **Role**: 단일 NS 안에서 권한
- **ClusterRole**: 클러스터 전체 (또는 cluster-scoped 리소스: Node, PV, ClusterRole 자체 등)

verbs 종류:
- `get`, `list`, `watch` (읽기)
- `create`, `update`, `patch`, `delete` (쓰기)
- `*` (전부)

### 1.3 RoleBinding / ClusterRoleBinding — "결합"

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: default
subjects:
  - kind: ServiceAccount
    name: my-sa
    namespace: default
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

이걸 적용하면: `default` NS의 `my-sa` 가 `pod-reader` Role을 갖게 됨.

### 1.4 매트릭스로 정리

|  | namespace 한정 | cluster-wide |
|---|---|---|
| 권한 정의 | `Role` | `ClusterRole` |
| 권한 결합 | `RoleBinding` | `ClusterRoleBinding` |

조합 규칙:
- `RoleBinding` + `Role` → 한 NS 안의 권한
- `RoleBinding` + `ClusterRole` → ClusterRole의 정의를 한 NS에서만 사용 (재사용 패턴)
- `ClusterRoleBinding` + `ClusterRole` → 클러스터 전역
- `ClusterRoleBinding` + `Role` → ❌ 불가능

### 1.5 권한 점검 명령

```bash
kubectl auth can-i list pods --as=system:serviceaccount:default:my-sa
kubectl auth can-i create deployments --as=system:serviceaccount:prod:deployer -n prod
```

`yes` / `no` 로 답해줍니다.

> **🧠 RBAC 디버깅의 1번 도구는 `kubectl auth can-i`**
> 권한 문제를 *log/error 로 추적하는 건 시간 낭비* — K8s 가 제공하는 자체 점검 명령으로 즉시 yes/no 가 나온다.
> `--as` 플래그로 *그 SA 인 척* 시뮬레이션할 수 있어, 실제 배포 전에 RBAC 검증 가능.

## 2. Helm — K8s 패키지 매니저

### 2.1 왜 필요한가

매니페스트 직접 관리의 한계:
- 환경별 변수 (이미지 태그, replicas) 수동 치환 → 휴먼 에러
- 매니페스트 10개 묶음을 한 번에 install/upgrade 불편
- 의존성 (예: 앱 + Redis subchart) 관리 불편

Helm이 해결:
- 차트 (Chart) = 매니페스트 템플릿 + 기본 values
- `values.yaml` 로 환경 분리
- `helm install/upgrade/rollback/uninstall` 한 단어

### 2.2 차트 구조

```
mychart/
├── Chart.yaml             # 차트 메타 (이름, 버전)
├── values.yaml            # 기본 values
├── templates/
│   ├── _helpers.tpl       # 공용 함수 (예: full name 만들기)
│   ├── deployment.yaml    # Go template
│   ├── service.yaml
│   ├── ingress.yaml
│   └── configmap.yaml
├── charts/                # 의존 차트 (subchart)
└── README.md
```

### 2.3 템플릿 문법 미리보기

`templates/deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "mychart.fullname" . }}
  labels:
    {{- include "mychart.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "mychart.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "mychart.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: app
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          ports:
            - containerPort: {{ .Values.service.port }}
```

`values.yaml`:
```yaml
replicaCount: 3
image:
  repository: my-app
  tag: v1.0.0
service:
  port: 8080
```

### 2.4 install / upgrade / rollback

```bash
# 설치
helm install my-app ./mychart -n my-ns --create-namespace

# values 오버라이드
helm install my-app ./mychart -f values-prod.yaml --set image.tag=v2

# 업그레이드 (없으면 install)
helm upgrade --install my-app ./mychart -f values-prod.yaml

# 이전 버전으로 롤백
helm history my-app
helm rollback my-app 1

# 삭제
helm uninstall my-app
```

### 2.5 dry-run / template

```bash
# 매니페스트만 렌더링 (배포 안 함)
helm template my-app ./mychart > rendered.yaml

# 서버 측 dry-run (검증)
helm install my-app ./mychart --dry-run --debug
```

### 2.6 차트 검색 / 외부 차트 사용

```bash
helm search hub redis              # ArtifactHub 검색
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install my-redis bitnami/redis  # 정확한 버전: helm search repo bitnami/redis -l | head 로 확인 후 --version 18.X.Y 지정
```

> **🧠 `helm upgrade --install` + `helm template` 두 명령이면 90% 해결**
> 전자는 idempotent 배포 (CI/CD 에서 install/upgrade 분기 안 해도 됨), 후자는 *실제로 어떤 YAML 이 만들어지는지* 확인용.
> 차트가 의심스러울 땐 `helm template` 으로 렌더 결과를 먼저 `kubectl diff` 와 비교하라 — 운영 사고 90% 예방.

다음: [lab-01-rbac.md](./lab-01-rbac.md)

---

## 부록 A — RBAC를 한 문장으로

> **"누가(Subject) / 무엇을(Resource) / 어떻게(Verb) 할 수 있는가"** 를 정의하고,
> 그걸 모아둔 묶음(**Role**) 을 누군가(**RoleBinding**) 에게 부여하는 시스템.

```
[Subject]              [Verb]           [Resource]
ServiceAccount(앱)  →  get/list/watch  → pods
User(사람)         →  create/delete   → secrets
Group(팀)          →  *               → */*  ← 너무 강력! 운영 금지
```

## 부록 B — Helm 핵심 명령 한 줄 요약

```bash
# 차트 설치 (= apply의 helm 버전)
helm install <릴리즈명> <차트경로>

# 값 덮어쓰기
helm install my-app ./charts/order-service \
  --set image.repository=my-repo \
  --set replicaCount=5

# 별도 values 파일로 (실무: 환경별 분리)
helm install my-app ./charts/order-service -f values-prod.yaml

# 업그레이드 (재배포)
helm upgrade my-app ./charts/order-service -f values-prod.yaml

# 둘 다 처리: 없으면 install, 있으면 upgrade
helm upgrade --install my-app ./charts/order-service

# 미리보기 (apply 안 하고 렌더 결과만)
helm template my-app ./charts/order-service -f values-prod.yaml

# 이력 / 롤백
helm history my-app
helm rollback my-app 2

# 제거
helm uninstall my-app
```

## 부록 C — FAQ

### Q1. "기본 SA(default)는 권한이 있나요?"
원칙적으로 **없습니다**. 하지만 default SA는 K8s API에 토큰을 자동 마운트해주므로, 잘못 설정된 RBAC가 있으면 의도치 않은 권한이 생길 수 있어요. **운영 시 SA 명시적 지정 + 자동 마운트 비활성화** 권장:
```yaml
spec:
  serviceAccountName: my-app-sa
  automountServiceAccountToken: false   # API 호출 안 하면 끄기
```

### Q2. "Role과 ClusterRole 중 뭘 써야 하나?"
- 한 NS 안에서만 권한 → **Role**
- 여러 NS 가로질러야 함 → **ClusterRole + RoleBinding** (NS 단위로 부여)
- 클러스터 전역 권한 (Node 등 cluster-scoped) → **ClusterRole + ClusterRoleBinding**

### Q3. "Helm vs Kustomize 무엇을 써야 하나?"
- 환경별 변형이 단순 (이미지 태그, replicas) → **Kustomize** (`kubectl apply -k` 내장)
- 외부에 차트로 배포/공유 / 복잡한 템플릿 / 패키지 매니저처럼 → **Helm**
- 둘 다 함께 쓰는 케이스도 있음 (Helm 차트를 Kustomize로 후처리)

### Q4. "Helm 템플릿의 `{{- if X }}` 의 `-` 는 뭔가요?"
공백/줄바꿈을 제거하는 트림 마커. 없으면 렌더 후 빈 줄이 잔뜩 생김.
- `{{ X }}` : 값만 삽입
- `{{- X }}`: 앞쪽 공백/줄바꿈 제거
- `{{ X -}}`: 뒤쪽 공백/줄바꿈 제거
- `{{- X -}}`: 양쪽 다 제거
