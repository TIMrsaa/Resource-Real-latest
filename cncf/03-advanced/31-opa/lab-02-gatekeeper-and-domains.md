# Lab 02 — Gatekeeper(K8s admission)와 하나의 엔진, 여러 영역

rego 정책을 K8s admission으로 강제하고, 같은 정책이 CI에서도 쓰이는 것을 확인한 뒤, Kyverno(32)와의 선택 기준을 세웁니다.

전제: kind, kubectl, helm, conftest. lab-01의 rego.

## Step 1. 클러스터와 Gatekeeper

```bash
kind create cluster --name opa -q

helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts >/dev/null 2>&1
helm install gatekeeper gatekeeper/gatekeeper -n gatekeeper-system --create-namespace >/dev/null
kubectl -n gatekeeper-system rollout status deploy/gatekeeper-controller-manager --timeout=180s
kubectl get crd | grep gatekeeper | head -4
```

## Step 2. ConstraintTemplate — rego를 담은 재사용 템플릿

```bash
kubectl apply -f - <<'EOF'
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata: { name: k8srequiredlabels }
spec:
  crd:
    spec:
      names: { kind: K8sRequiredLabels }
      validation:
        openAPIV3Schema:
          type: object
          properties:
            labels: { type: array, items: { type: string } }
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredlabels
        violation[{"msg": msg}] {
          required := input.parameters.labels[_]
          not input.review.object.metadata.labels[required]
          msg := sprintf("missing required label: %v", [required])
        }
EOF
sleep 5
kubectl get constrainttemplate
```

✅ **ConstraintTemplate = rego + 파라미터 스키마**(theory §4) — 재사용 가능한 정책 템플릿이 새 CRD(K8sRequiredLabels)를 만듭니다.

## Step 3. Constraint — 템플릿을 구체적으로 적용

```bash
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata: { name: ns-require-team }
spec:
  enforcementAction: dryrun          # ★ 07의 audit부터 (dryrun→deny)
  match:
    kinds: [{ apiGroups: [""], kinds: ["Namespace"] }]
  parameters:
    labels: ["team"]
EOF
sleep 5

# team 라벨 없는 네임스페이스 (dryrun이라 생성은 되고 위반 기록)
kubectl create ns test-ns 2>&1 | tail -1
sleep 8

echo "=== dryrun 위반 확인 ==="
kubectl get k8srequiredlabels ns-require-team -o jsonpath='{.status.violations}' 2>/dev/null | python3 -m json.tool 2>/dev/null | head -8 || \
  kubectl describe k8srequiredlabels ns-require-team | grep -A3 -i violation | head -5
```

✅ **dryrun은 위반을 기록만**(07의 audit) — 기존 리소스와 새 리소스의 위반을 파악한 뒤 enforce로.

## Step 4. enforce로 전환 — 차단

```bash
kubectl patch k8srequiredlabels ns-require-team --type merge -p '{"spec":{"enforcementAction":"deny"}}'
sleep 5

echo "=== team 라벨 없이 네임스페이스 생성 (차단되어야) ==="
kubectl create ns test-ns2 2>&1 | tail -2

echo ""
echo "=== team 라벨 있으면 통과 ==="
kubectl create ns test-ns3 --dry-run=client -o yaml | \
  kubectl label -f - team=platform --local -o yaml | kubectl apply -f - 2>&1 | tail -1
```

예상: 라벨 없으면 admission 거부, 있으면 통과. ✅ **audit→enforce 이행 곡선**(07·21) — Gatekeeper의 enforcementAction으로.

## Step 5. 같은 정책, 다른 영역 — CI (conftest)

```bash
cd ~/cncf-lab/opa

# lab-01의 k8s.rego를 CI에서 매니페스트 검사에 (cicd 24)
cat > manifest.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: test }
spec:
  containers:
    - { name: app, image: nginx:latest }
EOF

# conftest용으로 rego 조정 (deny 규칙)
cat > policy/deny.rego <<'EOF'
package main
deny[msg] {
    input.kind == "Pod"
    c := input.spec.containers[_]
    endswith(c.image, ":latest")
    msg := sprintf("container '%s' uses :latest", [c.name])
}
EOF
mkdir -p policy && mv policy/deny.rego policy/ 2>/dev/null || true

conftest test manifest.yaml -p policy/ 2>&1 | tail -4

cat <<'EOF'

★ 같은 rego 사고가 두 영역에서 (theory §5):
  Gatekeeper: K8s admission (배포 시점) — ConstraintTemplate/Constraint
  conftest:   CI 파이프라인 (파이프라인) — cicd 24
  → 조직이 rego 하나로 admission·CI를 통일 (07의 관통 엔진)
EOF
```

## Step 6. 다영역 지도 — 하나의 엔진

```bash
cat <<'EOF'
=== OPA가 덮는 영역 (theory §5) ===
① K8s admission (Gatekeeper) — "이 Pod 허용?"
② CI (conftest) — "이 매니페스트/IaC 정책 준수?" (cicd 24)
③ 앱 인가 (OPA 서버/라이브러리) — "이 사용자가 이 API를?"
④ Terraform plan (conftest) — "이 인프라 변경 규정?"
⑤ Envoy ext_authz (23) — "이 프록시 요청 인가요?"
⑥ Kafka·SQL·CI/CD 시스템 인가

★ 07의 관통 엔진:
  "prod에는 서명된 이미지만"을
  → admission(배포)·CI(빌드)·런타임(인가)에서 같은 rego로
  → 정책의 단일 진실 소스(SSOT)
  → 조직 전체가 하나의 정책 언어
EOF
```

## Step 7. Kyverno와의 선택 (32의 예고)

```bash
cat <<'EOF'
=== OPA/Gatekeeper vs Kyverno(32) (cicd 24 완성) ===
| | OPA/Gatekeeper | Kyverno |
|---|---|---|
| 언어 | rego (전용, 학습 곡선) | YAML/CRD (K8s 친숙) |
| 범위 | 범용 (K8s·CI·앱·TF·Envoy) | K8s 전용 |
| 강점 | 한 언어로 전 영역, 복잡 로직 | 진입 쉬움, generate·mutate 강함 |
| 약점 | rego 학습 | K8s 밖 못 씀 |

선택:
  조직 전체 정책 통일(다영역) → OPA
  K8s 정책만 + rego 부담 회피 → Kyverno
  함께: CI·다영역은 OPA(conftest), K8s admission은 Kyverno
        (실제로 이 조합이 흔합니다 — 32에서 Kyverno를 배우고 판단)

★ 25(메시)·27(런타임)에서 본 "범용 vs 전용"의 정책 엔진판
EOF
```

## Step 8. 산출물

```markdown
# OPA 종합 카드
## 결정 분리
- PEP(집행: 앱·API서버·CI)가 PDP(OPA)에 질의 → rego로 결정
- input(질의) + data(배경) + rego(규칙)

## Gatekeeper
- ConstraintTemplate(rego) + Constraint(적용)
- enforcementAction: dryrun→deny (07·21의 audit→enforce)

## 다영역 (07의 관통 엔진)
- admission·CI·앱 인가·Terraform·Envoy를 같은 rego로
- 정책의 단일 진실 소스

## 선택 (vs Kyverno 32)
- 다영역 통일 → OPA / K8s만 + 쉬움 → Kyverno / 함께도 흔함
```

## 정리

```bash
bash cleanup.sh
```
