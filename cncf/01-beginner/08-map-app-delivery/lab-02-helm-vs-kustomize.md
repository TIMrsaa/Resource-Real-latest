# Lab 02 — 2단 해부: 템플릿과 오버레이, 그리고 3단이 둘을 소비하는 법

같은 앱을 Helm과 Kustomize로 각각 만들어 철학의 차이를 눈으로 보고, ArgoCD가 둘을 어떻게 렌더링하는지 확인합니다.

전제: kind, kubectl, helm, kustomize(또는 `kubectl -k`).

## Step 1. 클러스터

```bash
kind create cluster --name delivery -q
mkdir -p ~/cncf-lab/delivery && cd ~/cncf-lab/delivery
```

## Step 2. Helm — 템플릿 + values

```bash
helm create app >/dev/null && cd app
# 템플릿의 실체: YAML을 '문자열'로 다루는 Go template
head -12 templates/deployment.yaml

# values로 환경 분기
cat > values-prod.yaml <<'EOF'
replicaCount: 3
image: { tag: "1.27" }
resources:
  limits: { cpu: 500m, memory: 256Mi }
EOF

echo "--- dev 렌더링 (기본 values) ---"
helm template app . | grep -E "replicas:|image:" | head -3
echo "--- prod 렌더링 (values-prod) ---"
helm template app . -f values-prod.yaml | grep -E "replicas:|image:" | head -3
cd ..
```

예상: 같은 템플릿이 values에 따라 다른 매니페스트로. ✅ **템플릿은 렌더링 전까지 유효한 YAML이 아닙니다** — 들여쓰기·따옴표 버그가 이 층의 고전 고통(`nindent`·`toYaml`).

## Step 3. Kustomize — 베이스 + 오버레이

```bash
mkdir -p ks/base ks/overlays/prod && cd ks
cat > base/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: app }
spec:
  replicas: 1
  selector: { matchLabels: { app: app } }
  template:
    metadata: { labels: { app: app } }
    spec:
      containers:
        - name: app
          image: nginx:1.26
EOF
cat > base/kustomization.yaml <<'EOF'
resources: [deployment.yaml]
EOF

cat > overlays/prod/kustomization.yaml <<'EOF'
resources: [../../base]
replicas:
  - name: app
    count: 3
images:
  - name: nginx
    newTag: "1.27"
patches:
  - target: { kind: Deployment, name: app }
    patch: |
      - op: add
        path: /spec/template/spec/containers/0/resources
        value: { limits: { cpu: 500m, memory: 256Mi } }
EOF

echo "--- base ---"
kubectl kustomize base | grep -E "replicas:|image:" | head -3
echo "--- prod 오버레이 ---"
kubectl kustomize overlays/prod | grep -E "replicas:|image:|cpu:" | head -4
cd ..
```

예상: 베이스는 그대로 유효한 YAML이고, 오버레이가 그것을 **병합·패치**합니다. ✅ **끝까지 YAML** — 템플릿 문법이 없어 에디터·린터·스키마 검증이 그대로 작동합니다(문법 오염 없음).

## Step 4. 철학 대비 — 언제 무엇을

```bash
cat <<'EOF'
| 상황 | 선택 | 이유 |
|------|------|------|
| 남에게 배포할 소프트웨어(차트 공유) | Helm | 버저닝·저장소·설치 상태(Release) |
| 우리 조직의 dev/stage/prod 변형     | Kustomize | 오버레이가 정확히 그 문제를 위한 것 |
| 복잡한 조건/루프가 필요             | Helm | 템플릿의 표현력 (단, 복잡도가 곧 부채) |
| 스키마 검증·정적 분석 중시          | Kustomize | 항상 유효한 YAML |
| 외부 컴포넌트 설치 + 우리 앱 변형   | 둘 다   | 실무의 표준 조합 (ArgoCD가 둘 다 렌더링) |
EOF
```

## Step 5. 3단이 2단을 소비합니다 — ArgoCD의 렌더링

```bash
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1
helm install argocd argo/argo-cd -n argocd --create-namespace \
  --set configs.params."server\.insecure"=true >/dev/null
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s

cat <<'EOF'
ArgoCD의 repo-server가 하는 일 (cicd 27에서 소스로 본 그것):
  source.path에 Chart.yaml이 있으면      → helm template 실행
  source.path에 kustomization.yaml이 있으면 → kustomize build 실행
  둘 다 없으면                            → 순수 YAML 그대로
  → 결과 매니페스트를 application-controller가 클러스터와 비교(diff)
★ 즉 2단(패키징)은 3단(배달)의 '입력 형식'일 뿐 — 경쟁 관계가 아닙니다
EOF

kubectl -n argocd exec deploy/argocd-repo-server -- which helm kustomize 2>/dev/null || \
  echo "(repo-server 이미지에 helm·kustomize 바이너리가 내장돼 있습니다)"
```

✅ theory §1의 판정 규칙이 실물로: **"Helm vs ArgoCD"는 성립하지 않습니다** — ArgoCD가 Helm을 실행합니다.

## Step 6. 렌더링 시점 논쟁 체험

```bash
cat <<'EOF'
같은 앱, 두 가지 GitOps 저장소 전략:
[A] CD 렌더 (일반적)
    Git: Chart + values-prod.yaml
    장점: 저장소 단순, 업스트림 차트 갱신 쉬움
    단점: PR diff가 "values 한 줄" — 실제 매니페스트 변화(사이드카 추가?)가 안 보임

[B] CI 렌더 (rendered manifests 패턴)
    Git: helm template 결과인 완성 YAML (CI가 커밋)
    장점: diff가 정직 — 무엇이 클러스터에 갈지 리뷰에 그대로 보임 (cicd 24의 감사 관점)
    단점: 저장소가 커지고, CI 파이프라인 한 겹 추가

질문: 우리 조직에서 "Git이 진실"의 정밀도는 어느 수준이어야 하는가요? (cicd 14)
EOF
```

## Step 7. 산출물

```markdown
# 2단·3단에서 확인한 것
- Helm: 템플릿(문자열) + values → 렌더링 전까지 YAML이 아님
- Kustomize: 베이스 + 패치 → 항상 유효한 YAML, 검증 도구 그대로
- 조합이 표준: 외부 컴포넌트는 Helm, 우리 앱 변형은 Kustomize
- 3단이 2단을 실행합니다 (repo-server) → 사다리의 단은 소비 관계이지 경쟁이 아닙니다
- 렌더링 시점: CI(정직한 diff) vs CD(단순 저장소) — 조직의 감사 요구가 결정
```

## 정리

```bash
bash cleanup.sh
```
