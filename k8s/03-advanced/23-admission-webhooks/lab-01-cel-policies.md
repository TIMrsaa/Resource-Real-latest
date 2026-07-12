# Lab 01 — ValidatingAdmissionPolicy: 정책 3종 작성

## Step 1. 정책 ① — :latest 태그 금지 (Warn으로 시작)

```bash
kubectl create ns vap-lab
kubectl label ns vap-lab policy=enforced

cat <<'EOF' | kubectl apply -f -
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata: { name: require-image-tag }
spec:
  matchConstraints:
    resourceRules:
    - apiGroups: ["apps"]
      apiVersions: ["v1"]
      operations: ["CREATE","UPDATE"]
      resources: ["deployments"]
  validations:
  - expression: "object.spec.template.spec.containers.all(c, c.image.contains(':') && !c.image.endsWith(':latest'))"
    message: "모든 컨테이너 이미지는 명시적 태그 필수 (:latest 금지)"
    reason: Invalid
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata: { name: require-image-tag-warn }
spec:
  policyName: require-image-tag
  validationActions: [Warn, Audit]          # 1단계: 경고만
  matchResources:
    namespaceSelector:
      matchLabels: { policy: enforced }
EOF
```

```bash
# 위반 배포 — 경고가 뜨지만 성공합니다
kubectl create deployment bad --image=nginx -n vap-lab
```

예상 출력:
```
Warning: Validation failed for ValidatingAdmissionPolicy 'require-image-tag' ... 모든 컨테이너 이미지는 명시적 태그 필수
deployment.apps/bad created          ← 만들어지긴 함 (Warn 모드)
```

✅ **점진 도입의 1단계**: 개발자는 경고를 보고 고칠 시간을 얻고, 운영자는 Audit 로그로 위반 현황을 셉니다.

## Step 2. Deny로 승격

```bash
kubectl patch validatingadmissionpolicybinding require-image-tag-warn \
  --type=merge -p '{"spec":{"validationActions":["Deny"]}}'

kubectl create deployment bad2 --image=nginx -n vap-lab
```

예상 출력:
```
The deployments "bad2" is invalid: : ValidatingAdmissionPolicy 'require-image-tag' ... denied request: 모든 컨테이너 이미지는 명시적 태그 필수 (:latest 금지)
```

```bash
kubectl apply -f - <<'EOF'                            # → created
apiVersion: apps/v1
kind: Deployment
metadata:
  name: good
  namespace: vap-lab
  labels: { app: good }
spec:
  replicas: 1
  selector:
    matchLabels: { app: good }
  template:
    metadata:
      labels: { app: good }
    spec:
      containers:
        - name: nginx
          image: public.ecr.aws/nginx/nginx:1.27        # 명시적 태그 — 정책 통과
EOF
kubectl create deployment anywhere --image=nginx                                     # default ns → 그냥 됨 (바인딩 밖)
```

✅ 거부는 **vap-lab(라벨 매칭)에서만** — 바인딩의 namespaceSelector가 폭발 반경을 통제합니다.

## Step 3. 정책 ② — 비용 라벨 강제 (옵셔널 필드 다루기)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata: { name: require-cost-label }
spec:
  matchConstraints:
    resourceRules:
    - {apiGroups: ["apps"], apiVersions: ["v1"], operations: ["CREATE"], resources: ["deployments"]}
  validations:
  - expression: "has(object.metadata.labels) && 'cost-center' in object.metadata.labels && object.metadata.labels['cost-center'].matches('^team-[a-z]+$')"
    message: "metadata.labels에 cost-center=team-<이름> 필수"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata: { name: require-cost-label-binding }
spec:
  policyName: require-cost-label
  validationActions: [Deny]
  matchResources:
    namespaceSelector: { matchLabels: { policy: enforced } }
EOF

kubectl create deployment nolabel --image=public.ecr.aws/nginx/nginx:1.27 -n vap-lab          # → 거부
kubectl create deployment labeled --image=public.ecr.aws/nginx/nginx:1.27 -n vap-lab \
  --dry-run=client -o yaml | kubectl label --local -f - cost-center=team-shop -o yaml | kubectl apply -f -   # → 성공
```

✅ `has()`와 `in` — **없을 수도 있는 필드**를 안전하게 다루는 CEL 패턴. (없는 필드에 바로 접근하면 평가 에러로 요청이 통째로 거부됩니다)

## Step 4. 정책 ③ — 파라미터화: replicas 상한을 ns마다 다르게

정책에 숫자를 하드코딩하지 않고 **params 객체**로 주입하는 고급 패턴:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata: { name: max-replicas }
spec:
  paramKind: { apiVersion: v1, kind: ConfigMap }     # 파라미터를 ConfigMap에서
  matchConstraints:
    resourceRules:
    - {apiGroups: ["apps"], apiVersions: ["v1"], operations: ["CREATE","UPDATE"], resources: ["deployments"]}
  validations:
  - expression: "object.spec.replicas <= int(params.data.maxReplicas)"
    messageExpression: "'replicas는 최대 ' + params.data.maxReplicas + '까지 (cost guard)'"
---
apiVersion: v1
kind: ConfigMap
metadata: { name: replica-limit, namespace: vap-lab }
data: { maxReplicas: "5" }
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata: { name: max-replicas-binding }
spec:
  policyName: max-replicas
  paramRef: { name: replica-limit, namespace: vap-lab, parameterNotFoundAction: Deny }
  validationActions: [Deny]
  matchResources:
    namespaceSelector: { matchLabels: { policy: enforced } }
EOF

kubectl scale deployment good -n vap-lab --replicas=10
```

예상 출력:
```
... denied request: replicas는 최대 5까지 (cost guard)
```

✅ **정책(식)과 한도(데이터)의 분리** — 같은 정책을 ns마다 다른 ConfigMap으로 바인딩하면 팀별 한도가 됩니다. Kyverno/Gatekeeper가 제품화한 패턴의 원형.

## 정리

vap-lab과 정책들은 lab-02 비교용으로 유지.
