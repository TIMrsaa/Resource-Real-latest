# Lab 01 — ARC를 EKS에 세우고, 잡이 Pod가 되는 것을 보다

k8s 파트에서 배운 CRD·컨트롤러·오토스케일링이 CI 인프라로 돌아옵니다. 워크플로 잡 하나가 Pod 하나가 되고, 끝나면 사라지는 것을 관찰합니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
kubectl config current-context   # 공유 EKS를 보고 있는지 확인
```

## Step 1. GitHub App 만들기 (PAT보다 안전)

ARC가 GitHub API로 잡 큐를 구독하려면 자격이 필요합니다.

```markdown
1. GitHub → Settings → Developer settings → GitHub Apps → New GitHub App
2. 권한:
   - Repository: Actions(Read), Administration(Read & Write), Metadata(Read)
   - (조직 레벨이면 Organization: Self-hosted runners(Read & Write))
3. 설치: 실습용 저장소(또는 조직)에
4. 확보할 값: App ID, Installation ID, Private Key(.pem)
```

```bash
export GH_APP_ID=<앱 ID>
export GH_APP_INSTALL_ID=<설치 ID>
export GH_APP_KEY_PATH=~/Downloads/arc-lab.private-key.pem   # 다운로드한 파일

# 짧은 PAT 경로(실습 한정): repo + admin:org 스코프
# export GH_PAT=ghp_...
```

## Step 2. 실습 저장소 (⚠️ 반드시 private)

```bash
mkdir -p ~/ci-lab/arc/.github/workflows && cd ~/ci-lab/arc
git init -q && git config user.email l@e.com && git config user.name L
echo "# arc lab" > README.md
git add -A && git commit -qm "init" && git branch -M main

gh repo create cicd-lab-arc --private --source=. --push    # ★ private! (theory §5)
REPO_URL="https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)"
echo $REPO_URL
```

## Step 3. ARC 컨트롤러 설치

```bash
helm install arc \
  --namespace arc-systems --create-namespace \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --version 0.10.1

kubectl get pods -n arc-systems
kubectl get crd | grep -i runner        # AutoscalingRunnerSet 등
```

✅ k8s 30(Operator 패턴)의 실물 — CRD를 watch하며 Pod를 만드는 컨트롤러입니다. Karpenter(eks 17), Velero(k8s 36)와 같은 구조.

## Step 4. 러너 스케일셋 — 이름이 곧 `runs-on`

```bash
kubectl create ns arc-runners 2>/dev/null || true
kubectl -n arc-runners create secret generic arc-gh-app \
  --from-literal=github_app_id=$GH_APP_ID \
  --from-literal=github_app_installation_id=$GH_APP_INSTALL_ID \
  --from-file=github_app_private_key=$GH_APP_KEY_PATH

helm install eks-runners \
  --namespace arc-runners \
  --set githubConfigUrl="$REPO_URL" \
  --set githubConfigSecret=arc-gh-app \
  --set minRunners=0 \
  --set maxRunners=3 \
  --set "template.spec.containers[0].name=runner" \
  --set "template.spec.containers[0].image=ghcr.io/actions/actions-runner:latest" \
  --set "template.spec.containers[0].command={/home/runner/run.sh}" \
  oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version 0.10.1

kubectl get autoscalingrunnerset -n arc-runners
kubectl get pods -n arc-runners        # listener Pod만 (minRunners=0이니 러너는 아직 없습니다)
```

GitHub 쪽에서도 확인:

```bash
gh api "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/actions/runners" \
  -q '.runners[] | {name, status, labels: [.labels[].name]}' 2>/dev/null || echo "(러너 대기 상태)"
```

## Step 5. 잡이 Pod가 되는 순간

```bash
cat > .github/workflows/on-arc.yml <<'EOF'
name: on-arc
on: [push, workflow_dispatch]
jobs:
  where-am-i:
    runs-on: eks-runners          # ★ 스케일셋 이름
    steps:
      - name: 나는 어디서 도는가
        run: |
          echo "hostname : $(hostname)"
          echo "이것은 Pod의 이름이다"
          cat /etc/os-release | head -2
      - name: 클러스터 안에 있는가 (VPC 접근이 이 러너의 존재 이유)
        run: |
          getent hosts kubernetes.default.svc && echo "✅ 클러스터 DNS 도달" || echo "DNS 불가"
EOF
git add -A && git commit -qm "ci: run on ARC" && git push -q
```

다른 터미널에서 러너 Pod의 생성과 소멸을 감시:

```bash
kubectl get pods -n arc-runners -w
```

예상 시퀀스:

```
eks-runners-xxxxx-runner-abc   Pending    ← ARC가 잡을 감지하고 Pod 생성
                               ContainerCreating
                               Running    ← 잡 실행 중
                               Completed  → 삭제
```

✅ **잡 하나 = Pod 하나 = 러너 등록 1회.** 이것이 ephemeral입니다(theory §3). 로그도 확인:

```bash
sleep 60
gh run view --log 2>/dev/null | grep -E "hostname|클러스터 DNS" | head -3
```

`hostname`이 Pod 이름으로 나오고, 클러스터 DNS에 도달합니다 — **VPC 안에 있습니다.** 이것이 self-hosted의 이유이자 위험입니다.

## Step 6. 스케일 관찰 — 매트릭스가 Pod들을 만듭니다

```bash
cat > .github/workflows/scale.yml <<'EOF'
name: scale-demo
on: workflow_dispatch
jobs:
  parallel:
    runs-on: eks-runners
    strategy:
      matrix:
        shard: [1, 2, 3]
    steps:
      - run: |
          echo "shard ${{ matrix.shard }} on $(hostname)"
          sleep 45
EOF
git add -A && git commit -qm "ci: scale demo" && git push -q
gh workflow run scale.yml

# 감시: Pod 3개가 동시에 뜹니다 (maxRunners=3)
watch -n3 "kubectl get pods -n arc-runners --no-headers | grep runner | wc -l"
```

노드가 부족하면 Karpenter(eks 17)가 만듭니다:

```bash
kubectl get nodeclaims 2>/dev/null | tail -3 || echo "(Karpenter 미설치 — 기존 노드에 스케줄됨)"
kubectl get pods -n arc-runners -o wide | grep runner
```

✅ **CI 용량이 수요를 따라갑니다** — 잡 대기 → 러너 Pod → 노드 생성 → 실행 → 회수. 두 오토스케일러(ARC, Karpenter)가 사슬로 연결됩니다.

## Step 7. 콜드 스타트 측정 (튜닝의 근거)

```bash
gh run list --workflow=on-arc --limit 1 --json databaseId -q '.[0].databaseId' | while read ID; do
  gh api "repos/$(gh repo view --json nameWithOwner -q .nameWithOwner)/actions/runs/$ID/jobs" \
    -q '.jobs[] | {name, queued: .started_at, started: .started_at, completed: .completed_at}'
done
```

콜드 스타트의 구성: 러너 Pod 스케줄(초) + 이미지 pull(이미지 크기!) + 러너 등록(초) + (노드가 없으면 Karpenter 노드 생성 ~1분).

```markdown
# 콜드 스타트 줄이는 손잡이
- minRunners: 1~2 (상시 대기 — 노드 비용과 교환)
- 러너 이미지 슬림화 (04의 다이어트) + 노드에 이미지 프리풀
- Karpenter NodePool: CI 전용 + spot + 적절한 인스턴스 타입 폭(eks 17의 네거티브 설계)
```

## 정리

lab-02에서 격리와 IAM을 다룹니다. ARC는 유지.
