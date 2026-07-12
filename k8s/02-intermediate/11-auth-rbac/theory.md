# 이론 — 인증, 인가(RBAC), ServiceAccount, EKS 연동

> **🌱 17세 눈높이 비유: 회사 건물의 출입 시스템**
> - **인증** = 1층 게이트에서 사원증 확인. "김민준 맞네" — 신원만 확인하지 어디 들어갈지는 안 따짐.
> - **인가(RBAC)** = 각 층/방 카드키 권한. "개발 3팀 사무실(namespace)의 회의실(pods)을 예약(create)할 수 있는 사람"
> - **Role** = 권한 목록표 ("회의실 예약 가능, 비품창고 열람 가능")
> - **RoleBinding** = 그 목록표를 **누구에게** 발급할지의 발급 대장
> - **ServiceAccount** = 사람이 아니라 **로봇 청소기(Pod) 전용 사원증** — 로봇도 출입 권한이 필요합니다.

---

## 1. 인증 — "너 누구야?"

K8s에는 User/Group **리소스가 없습니다.** 인증 방식이 신원 문자열을 만들어낼 뿐:

| 방식 | 신원의 출처 | 비고 |
|------|------------|------|
| X.509 인증서 | 인증서의 CN(사용자)/O(그룹) | kubeadm 클러스터 기본. 폐기(revoke) 불가가 약점 |
| Bearer 토큰 / OIDC | IdP(구글/Okta...)의 JWT 클레임 | 기업 SSO 연동 표준 |
| **IAM (EKS)** | aws-iam-authenticator가 STS로 검증 | kubectl이 IAM 서명 토큰을 보냄 |
| ServiceAccount 토큰 | K8s가 발급한 JWT | **Pod(프로그램)용** — 유일하게 K8s가 관리하는 신원 |

> **💡 EKS의 인증 흐름**: `kubectl get pods` → kubeconfig의 exec 플러그인이 `aws eks get-token` 실행 → IAM 서명이 담긴 토큰 생성 → API 서버가 검증 → **access entries**에서 이 IAM ARN이 어떤 K8s 사용자/그룹으로 매핑되는지 조회. (옛 방식 aws-auth ConfigMap은 deprecated — access entries가 표준)

## 2. 인가 — RBAC 4종 세트

### 2.1 Role / ClusterRole — 권한의 "내용"

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role                      # ns 한정 (ClusterRole이면 metadata.namespace 없음)
metadata:
  namespace: dev
  name: pod-reader
rules:
- apiGroups: [""]               # "" = core 그룹 (pods, services...)
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list"]
```

- verbs: get/list/watch(읽기), create/update/patch/delete(쓰기), 그리고 특수한 것들 — `pods/exec`의 create(셸 접속!), `pods/portforward` 등 **하위 리소스** 주의
- **RBAC는 허용만 있습니다(deny 규칙 없음)** — 아무 규칙에도 안 걸리면 거부. 그래서 "기본 거부"가 자동으로 성립

### 2.2 RoleBinding / ClusterRoleBinding — 권한의 "대상과 범위"

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: dev
  name: dev-readers
subjects:
- kind: User                    # 인증이 만들어낸 문자열과 일치해야 함
  name: minjun
- kind: Group
  name: dev-team
- kind: ServiceAccount
  name: ci-bot
  namespace: dev
roleRef:                        # 단 하나만, 생성 후 불변
  kind: Role                    # 또는 ClusterRole
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### 2.3 조합 4가지 (시험 포인트)

| Role 종류 | Binding 종류 | 효과 |
|-----------|-------------|------|
| Role | RoleBinding | 그 ns의 권한을 그 ns에서 |
| ClusterRole | ClusterRoleBinding | 전역 권한 (모든 ns + 클러스터 리소스) |
| **ClusterRole** | **RoleBinding** | **전역 정의를 특정 ns에만 적용** ← 실무 표준 (재사용) |
| Role | ClusterRoleBinding | 불가능 |

### 2.4 내장 ClusterRole

| 이름 | 권한 |
|------|------|
| view | 읽기 (secrets 제외!) — 잘 설계된 본보기 |
| edit | 읽기+쓰기 (RBAC 수정 불가) |
| admin | ns 안 전부 (RBAC 포함) |
| cluster-admin | 신 — 누구에게도 함부로 binding하지 말 것 |

## 3. ServiceAccount — Pod의 신분증

```yaml
spec:
  serviceAccountName: app-sa        # 미지정 시 "default" SA
  automountServiceAccountToken: false  # API 안 쓰는 앱은 토큰 마운트 끄기 (보안)
```

- 토큰은 **projected volume**으로 마운트되는 단기 JWT (기본 1시간, 자동 갱신). 옛날의 무기한 Secret 토큰은 폐지됨
- 토큰 위치: `/var/run/secrets/kubernetes.io/serviceaccount/token` — 컨테이너가 탈취당하면 이 토큰의 권한이 공격자의 권한입니다. **default SA에 권한을 주지 마세요**
- EKS 확장: SA에 **IAM 역할**을 연결해 AWS API 권한을 주는 것이 IRSA/Pod Identity (모듈 08 lab에서 사용, eks 파트 09에서 해부)

## 4. 권한 디버깅 도구

```bash
kubectl auth can-i create deployments -n dev                    # 나
kubectl auth can-i delete pods --as=minjun -n dev               # 남 흉내 (impersonation)
kubectl auth can-i --list --as=system:serviceaccount:dev:ci-bot # 전체 목록
kubectl auth whoami                                             # 내 신원 확인
```

## 5. 소스코드에서 확인하기

- RBAC 평가기: `plugin/pkg/auth/authorizer/rbac/rbac.go` — `Authorize()`가 "규칙 순회하며 하나라도 맞으면 allow"의 구현
- 내장 ClusterRole 정의: `plugin/pkg/auth/authorizer/rbac/bootstrappolicy/policy.go` — view/edit/admin의 실제 내용

## 요약 카드

| 질문 | 답 |
|------|----|
| K8s의 사용자 DB? | 없음 — 인증 방식이 신원 문자열 생성 (EKS는 IAM) |
| RBAC에 deny 규칙? | 없음 — 허용 목록만, 기본 거부 |
| 실무 표준 조합? | ClusterRole + RoleBinding (정의 재사용, ns 한정 적용) |
| Pod의 신원? | ServiceAccount (미지정 시 default — 권한 주지 말 것) |
| 권한 테스트? | `kubectl auth can-i ... --as=...` |
