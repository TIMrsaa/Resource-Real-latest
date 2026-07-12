# Lab 01 — 가상 클러스터 2개로 fleet 운영 맛보기

vCluster로 독립 API 서버 두 개를 세우고(34의 "별관"이 실물로), base/overlay 표준화와 drift 탐지 — fleet 운영의 최소 사이클을 돕니다.

## Step 1. vCluster CLI와 클러스터 2개

```bash
# CLI 설치 (https://www.vcluster.com/docs)
curl -L -o vcluster "https://github.com/loft-sh/vcluster/releases/latest/download/vcluster-linux-amd64" \
  && chmod +x vcluster && sudo mv vcluster /usr/local/bin/

vcluster create cluster-a -n vc-a --connect=false
vcluster create cluster-b -n vc-b --connect=false
kubectl get pods -n vc-a    # 가상 CP가 Pod로! (API server+데이터스토어가 한 세트)
```

✅ 호스트 입장에선 StatefulSet 하나 — 그런데 그 안엔 **완전한 API 서버**가 삽니다. 34 스펙트럼 ③의 실물: CRD·버전·웹훅을 테넌트별로 가질 수 있는 이유가 이 구조입니다.

## Step 2. 두 세계가 정말 독립인지 확인

```bash
vcluster connect cluster-a -n vc-a -- kubectl get ns     # 신품 클러스터의 ns 목록
vcluster connect cluster-a -n vc-a -- kubectl create ns only-in-a
vcluster connect cluster-b -n vc-b -- kubectl get ns only-in-a 2>&1 | tail -1   # NotFound!
```

✅ a에 만든 ns가 b엔 없습니다 — 독립 API 서버들. 이제부터 이 둘이 우리의 "fleet"입니다.

## Step 3. 표준의 구조 — base와 overlay

```bash
mkdir -p fleet/{base,overlays/cluster-a,overlays/cluster-b}

cat > fleet/base/kustomization.yaml <<'EOF'
resources: [app.yaml]
EOF
cat > fleet/base/app.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: standard-app, namespace: default }
spec:
  replicas: 2
  selector: { matchLabels: { app: standard-app } }
  template:
    metadata: { labels: { app: standard-app } }
    spec:
      containers:
      - name: app
        image: ghcr.io/stefanprodan/podinfo:6.7.1
        env: [{ name: PODINFO_UI_MESSAGE, value: base }]
        resources: { requests: { cpu: 100m, memory: 64Mi } }
EOF

# 클러스터별 차이는 overlay "에만" (theory §2의 규율)
for c in cluster-a cluster-b; do
cat > fleet/overlays/$c/kustomization.yaml <<EOF
resources: ["../../base"]
patches:
- patch: |-
    - op: replace
      path: /spec/template/spec/containers/0/env/0/value
      value: $c
  target: { kind: Deployment, name: standard-app }
EOF
done
```

## Step 4. fleet 전개 — "클러스터 목록 × 표준"

```bash
for c in a b; do
  vcluster connect cluster-$c -n vc-$c -- kubectl apply -k fleet/overlays/cluster-$c
done
for c in a b; do
  echo "=== cluster-$c ==="
  vcluster connect cluster-$c -n vc-$c -- kubectl get deploy standard-app -o jsonpath='{.spec.template.spec.containers[0].env[0].value}'; echo
done
```

예상: 같은 base, 다른 메시지(cluster-a / cluster-b). ✅ 이 for 루프가 곧 ArgoCD **ApplicationSet의 수동판**입니다 — 실전에선 git push가 이 루프를 대신합니다(39).

## Step 5. drift — fleet의 숙적을 재현하고 탐지

누군가 cluster-b에서 "급해서" 직접 고쳤습니다:

```bash
vcluster connect cluster-b -n vc-b -- kubectl scale deploy standard-app --replicas=5
```

fleet 운영자의 무기 — 선언 대비 diff 스캔:

```bash
for c in a b; do
  echo "=== drift check: cluster-$c ==="
  vcluster connect cluster-$c -n vc-$c -- kubectl diff -k fleet/overlays/cluster-$c | grep -E "^[+-].*replicas" || echo "  drift 없음"
done
```

예상: cluster-b에서만 `- replicas: 5 / + replicas: 2`. ✅ **클러스터가 N개면 이 스캔이 사람 눈을 대체해야 합니다** — GitOps의 selfHeal(39)은 이 diff를 자동 원복까지 하는 것. 원복:

```bash
vcluster connect cluster-b -n vc-b -- kubectl apply -k fleet/overlays/cluster-b
```

## Step 6. fleet 운영 문서 (산출물)

```markdown
# fleet 표준 운영
- 구조: base(표준) + overlays/<cluster>(차이) — base 직수정 금지
- 전개: ApplicationSet(prod) / 이 랩의 루프(이해용)
- drift: 주기 diff 스캔 + selfHeal — "급해서 직접"은 다음 파도에서 증발함을 전파
- 버전 스큐: fleet 내 1마이너 이내 — 업그레이드는 staging 파도 → prod 파도 (21)
- 신규 클러스터 온보딩 = overlay 폴더 하나 + 클러스터 등록 (표준이 곧 온보딩)
```

## 정리

vcluster 2개는 lab-02에서도 쓰지 않으므로 여기서 정리해도 됩니다 — 단 cleanup.sh가 일괄 처리합니다.
