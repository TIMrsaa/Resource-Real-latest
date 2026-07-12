# Lab 01 — Preflight: 게이트를 통과해야 출발합니다

theory §3의 게이트 G1~G4를 실제 명령으로 만듭니다. (G5 백업은 모듈 36에서 완성)

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
mkdir -p ~/upgrade-lab && cd ~/upgrade-lab
```

## Step 1. G1 — EKS cluster insights

```bash
aws eks list-insights --cluster-name $CLUSTER --region $AWS_REGION \
  --query 'insights[].{name:name,category:category,status:insightStatus.status}' --output table
```

예상: `UPGRADE_READINESS` 카테고리 항목들이 PASSING/WARNING/ERROR로. 규칙은 단순합니다 — **ERROR 1건이라도 있으면 게이트 폐쇄.** 상세와 권고까지:

```bash
INSIGHT_ID=$(aws eks list-insights --cluster-name $CLUSTER --region $AWS_REGION --query 'insights[0].id' --output text)
[ "$INSIGHT_ID" != "None" ] && aws eks describe-insight --cluster-name $CLUSTER --region $AWS_REGION --id $INSIGHT_ID \
  --query 'insight.{name:name,recommendation:recommendation}' --output json || echo "(인사이트 없음)"
```

✅ insights는 control plane **감사 로그(21)** 를 읽으므로 "어떤 클라이언트가 폐기 API를 실제 호출 중인지"까지 압니다 — 정적 스캔이 절대 못 보는 각도.

## Step 2. G2 — 폐기 API를 심고, 잡아봅니다 (Pluto)

탐지기를 믿으려면 탐지되는 걸 봐야 합니다. 일부러 옛 API를 심습니다:

```bash
cat > old-manifest.yaml <<'EOF'
apiVersion: policy/v1beta1        # 1.25에서 제거됨 → policy/v1 (reference 표)
kind: PodDisruptionBudget
metadata: { name: legacy-pdb }
spec:
  minAvailable: 1
  selector: { matchLabels: { app: x } }
EOF

pluto detect-files -d . 2>/dev/null \
  || echo "pluto 미설치 — https://github.com/FairwindsOps/pluto/releases 에서 받기"
```

예상 (pluto):

```
NAME         KIND                  VERSION           REPLACEMENT   REMOVED
legacy-pdb   PodDisruptionBudget   policy/v1beta1    policy/v1     true
```

Helm으로 배포된 것은 렌더링 결과를 봐야 하므로 별도 명령:

```bash
pluto detect-helm 2>/dev/null | head    # 릴리스된 차트 속 폐기 API
```

✅ 정적(Pluto)이 저장소·차트를, 동적(insights)이 런타임 호출을 — theory §4의 그물 두 겹을 직접 쳤습니다.

## Step 3. G3 — 애드온 호환표

목표 버전(예: 1.36)에서 각 애드온의 default 버전을 미리 적어둡니다 (eks 11의 그 기준):

```bash
for addon in vpc-cni coredns kube-proxy; do
  printf "%-12s " $addon
  aws eks describe-addon-versions --addon-name $addon --kubernetes-version 1.36 --region $AWS_REGION \
    --query 'addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion' --output text
done
```

✅ 이 목록이 실행 2단계(애드온 업그레이드)의 목표값이 됩니다. "CP만 올리고 애드온 방치"를 구조적으로 막는 장치.

## Step 4. G4 — PDB 전수 점검: 데드락 후보 색출

```bash
kubectl get pdb -A
# disruptionsAllowed=0 = drain이 영원히 막히는 지점
kubectl get pdb -A -o json | python3 -c "
import json,sys
bad=[p for p in json.load(sys.stdin)['items'] if p.get('status',{}).get('disruptionsAllowed',0)==0]
print('데드락 후보', len(bad),'건')
for p in bad: print(' -',p['metadata']['namespace']+'/'+p['metadata']['name'])"
```

후보가 나오면 업그레이드 전 해소: replicas 증설(가장 정석) 또는 PDB 완화. 이제 lab-02에서 쓸 **적정 PDB의 모범**을 만듭니다:

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ha-app
  labels: { app: ha-app }
spec:
  replicas: 3
  selector:
    matchLabels: { app: ha-app }
  template:
    metadata:
      labels: { app: ha-app }
    spec:
      containers:
        - name: ha-app
          image: public.ecr.aws/nginx/nginx:1.29-unprivileged
EOF
kubectl rollout status deploy/ha-app --timeout=90s
cat <<'EOF' | kubectl apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: ha-app-pdb }
spec:
  maxUnavailable: 1              # 3개 중 동시에 1개까지만 부재 허용
  selector: { matchLabels: { app: ha-app } }
EOF
kubectl get pdb ha-app-pdb
```

예상: `ALLOWED DISRUPTIONS: 1` — drain이 진행은 되면서(1개씩) 가용성 하한(2개)은 지켜지는 균형점.

## Step 5. 게이트 판정 (산출물)

```markdown
# Preflight 게이트 — 1.35 → 1.36 (판정: 통과 / 중단)
- [ ] G1 insights: ERROR 0건 (WARNING은 사유 기록 후 수용 가능)
- [ ] G2 폐기 API: Pluto 0건 + insights deprecation 0건
- [ ] G3 애드온: 1.36 default 버전 목록 확보
- [ ] G4 PDB: disruptionsAllowed=0 없음
- [ ] G5 백업(36) + 공지 + 롤백 계획(어느 전략인지 명시)
하나라도 미충족 → 시작하지 않습니다. CP는 되돌릴 수 없습니다.
```

## 정리

ha-app과 PDB는 lab-02의 재료 — 남겨둡니다. `rm old-manifest.yaml`만.
