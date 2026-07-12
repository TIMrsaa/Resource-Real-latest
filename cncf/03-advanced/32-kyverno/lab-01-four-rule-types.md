# Lab 01 — 네 규칙 타입: validate/mutate/generate/verifyImages

정책 엔진의 네 가지 능력을 각각 손으로 확인합니다 — 특히 generate(정책이 리소스를 만드는 것)의 독특함을.

전제: kind, kubectl, helm.

## Step 1. 클러스터와 Kyverno

```bash
kind create cluster --name kyverno -q

helm repo add kyverno https://kyverno.github.io/kyverno >/dev/null 2>&1
helm install kyverno kyverno/kyverno -n kyverno --create-namespace >/dev/null
kubectl -n kyverno rollout status deploy/kyverno-admission-controller --timeout=180s

kubectl get crd | grep kyverno | head -5
echo "→ ClusterPolicy, Policy, PolicyReport... 정책이 전부 CRD (theory §3)"
```

## Step 2. validate — 검사 (Audit부터)

```bash
kubectl apply -f - <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: require-non-root }
spec:
  background: true
  rules:
    - name: check-non-root
      match: { any: [{ resources: { kinds: [Pod] } }] }
      validate:
        failureAction: Audit            # ★ 07의 audit부터 (규칙 단위 — spec 단위 validationFailureAction은 폐기 예정)
        message: "containers must set runAsNonRoot: true"
        pattern:
          spec:
            containers:
              - securityContext:
                  runAsNonRoot: true
EOF
sleep 5

# 위반 Pod (Audit라 생성은 되고 기록)
kubectl run bad --image=nginx 2>&1 | tail -1
sleep 8

echo "=== PolicyReport로 위반 감사 (theory §3) ==="
kubectl get policyreport -A 2>/dev/null | head -3
kubectl get policyreport -A -o json 2>/dev/null | python3 -c "
import json,sys
for pr in json.load(sys.stdin)['items']:
    for r in pr.get('results',[]):
        if r.get('result')=='fail':
            print(f\"  FAIL: {r.get('policy')} — {r.get('message','')[:60]}\"); break
" 2>/dev/null | head -3
```

✅ **rego 없이 YAML 패턴으로 검사**(theory §2), 위반은 PolicyReport CRD로 감사(07). Audit→Enforce 전환은 `failureAction: Enforce`.

## Step 3. mutate — 거부 대신 고쳐서 통과

```bash
kubectl apply -f - <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: add-labels-and-security }
spec:
  rules:
    - name: add-team-label
      match: { any: [{ resources: { kinds: [Pod] } }] }
      mutate:
        patchStrategicMerge:
          metadata:
            labels:
              team: "{{ request.namespace }}"      # 변수 치환
          spec:
            securityContext:
              +(runAsNonRoot): true                # +() = 없으면 추가
EOF
sleep 5

kubectl run mutated --image=nginx
sleep 5
echo "=== mutate가 주입한 것 ==="
kubectl get pod mutated -o jsonpath='{.metadata.labels.team}'; echo " ← team 라벨 자동 주입"
kubectl get pod mutated -o jsonpath='{.spec.securityContext.runAsNonRoot}'; echo " ← runAsNonRoot 자동 주입"
```

예상: team 라벨과 runAsNonRoot가 자동 주입됨. ✅ **mutate는 거부가 아니라 수정**(theory §2) — "non-root 아니면 거부"(validate) vs "non-root로 만들어 통과"(mutate)의 차이.

## Step 4. ★ generate — 정책이 리소스를 만듭니다

```bash
kubectl apply -f - <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: default-networkpolicy }
spec:
  rules:
    - name: default-deny-netpol
      match: { any: [{ resources: { kinds: [Namespace] } }] }
      generate:
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        name: default-deny
        namespace: "{{ request.object.metadata.name }}"
        synchronize: true
        data:
          spec:
            podSelector: {}
            policyTypes: [Ingress, Egress]
EOF
sleep 5

echo "=== 새 네임스페이스 생성 → NetworkPolicy가 자동 생성되나요? ==="
kubectl create ns tenant-a
sleep 8
kubectl -n tenant-a get networkpolicy
```

예상: tenant-a에 `default-deny` NetworkPolicy가 **자동 생성**됨. ✅ **정책이 리소스를 만듭니다**(theory §2) — validate라면 "없다"고 경고만 했을 것을, generate는 만듭니다. Kyverno의 독특한 강점(OPA의 약점 영역).

```bash
echo ""
echo "=== synchronize: 누가 지우면 다시 만든다 ==="
kubectl -n tenant-a delete networkpolicy default-deny
sleep 8
kubectl -n tenant-a get networkpolicy
echo "→ synchronize: true 라 삭제해도 재생성 (선언 상태 유지)"
```

## Step 5. verifyImages — 서명 검증 (cicd 21)

```bash
kubectl apply -f - <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: verify-signature }
spec:
  webhookTimeoutSeconds: 30
  rules:
    - name: check-cosign
      match: { any: [{ resources: { kinds: [Pod] } }] }
      verifyImages:
        - imageReferences: ["ghcr.io/myorg/*"]
          failureAction: Audit          # 실습이라 Audit (verifyImages도 규칙 단위)
          attestors:
            - entries:
                - keyless:
                    subject: "https://github.com/myorg/*"
                    issuer: "https://token.actions.githubusercontent.com"
                    rekor: { url: https://rekor.sigstore.dev }
EOF
sleep 5

cat <<'EOF'
verifyImages (cicd 21의 그 admission 서명 검증):
  keyless: OIDC 신원 기반 (cosign — 21)
  match된 이미지가 서명되지 않았으면 거부(Enforce) 또는 기록(Audit)
  → 21에서 배운 "증명이 게이트"가 Kyverno의 규칙 타입으로 내장

★ OPA/Gatekeeper는 이것을 별도 구성해야 하지만 Kyverno는 내장
EOF
kubectl get clusterpolicy verify-signature -o jsonpath='{.spec.rules[0].verifyImages[0].imageReferences}'; echo
```

## Step 6. 정책 라이브러리 — 검증된 정책 재사용

```bash
cat <<'EOF'
Kyverno 정책 라이브러리 (https://kyverno.io/policies/):
  Pod Security Standards (baseline·restricted)
  best practices (require limits, disallow latest...)
  보안(권한 상승 금지, 호스트 경로 금지...)
  → 처음부터 rego 짜지 않고 검증된 정책을 kubectl apply

★ 정책도 재사용 — 07·24의 정책을 바퀴 재발명 없이
EOF
```

## Step 7. 산출물

```markdown
# Kyverno 네 규칙 타입 카드
- validate: 검사 (pattern/deny/cel) — Audit→Enforce (07)
- mutate: 변형 — 거부 아니라 고쳐서 통과 (기본값·사이드카 주입)
- generate: 생성 — 정책이 리소스를 만듭니다 (synchronize로 유지) ★ 독특
- verifyImages: cosign 서명 검증 내장 (cicd 21)
- 정책=CRD → PolicyReport 감사, GitOps 관리(14), RBAC
- rego 없이 K8s YAML (31의 학습 곡선 회피)
```

## 정리

lab-02에서 OPA와 직접 대비합니다. 유지.
