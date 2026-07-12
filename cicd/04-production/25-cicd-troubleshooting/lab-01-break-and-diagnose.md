# Lab 01 — 3대 고전 재현: 캐시 오염, 동시성 데드락, 거짓 초록

대표 장애를 직접 만들고, 진단 카드의 "가설 순서 → 확인 → 처방"을 그대로 밟습니다.

전제: gh CLI, docker.

## Step 1. 캐시 오염 재현 — 키가 입력을 안 담으면 (카드 1)

```bash
mkdir -p ~/ci-lab/trouble/.github/workflows && cd ~/ci-lab/trouble
git init -q . && git config user.email l@e.com && git config user.name L

echo '{"dependencies":{"left-pad":"1.0.0"}}' > package.json
cat > .github/workflows/cache-bug.yml <<'EOF'
name: cache-bug
on: [push, workflow_dispatch]
permissions: { contents: read }
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/cache@v4
        with:
          path: deps/
          key: deps-cache-v1            # 🐛 고정 키 — 입력(package.json)이 키에 없습니다!
      - name: 의존성 "설치" (캐시 없을 때만)
        run: |
          [ -d deps ] || { mkdir deps; cp package.json deps/installed.json; echo "실제 설치 수행"; }
          echo "=== 사용 중인 의존성 ==="; cat deps/installed.json
EOF
git add -A && git commit -qm "cache with fixed key"
gh repo create cicd-lab-trouble --public --source=. --push >/dev/null
sleep 60

# 의존성 변경 — 하지만 캐시는?
sed -i 's/1.0.0/2.0.0/' package.json
git add -A && git commit -qm "upgrade left-pad to 2.0.0" && git push -q
sleep 60
gh run view --log 2>/dev/null | grep -A1 "사용 중인 의존성" | tail -2
```

예상: 버전을 2.0.0으로 올렸는데 로그는 **1.0.0** — 고정 키가 옛 캐시를 재생했습니다. "고쳤는데 옛 결과"(카드 1)의 최소 재현. 진단 절차:

```bash
# 확인: 캐시 없이 강제 재실행 → 되면 캐시 확정 (카드 1의 확인법)
# 처방: 키에 입력 해시 포함
sed -i "s|key: deps-cache-v1|key: deps-cache-v2-\${{ hashFiles('package.json') }}|" \
  .github/workflows/cache-bug.yml
git add -A && git commit -qm "fix: cache key includes input hash" && git push -q
sleep 60
gh run view --log 2>/dev/null | grep -A1 "사용 중인 의존성" | tail -2
```

예상: 이제 2.0.0. ✅ **캐시 키 = 입력의 함수**여야 합니다(19의 원리) — v2 접두사는 오염된 옛 캐시의 즉시 무효화(처방의 두 번째 수).

## Step 2. 동시성 데드락 재현 — 배포가 줄을 서서 굳습니다 (카드 3)

```bash
cat > .github/workflows/deploy-stuck.yml <<'EOF'
name: deploy-stuck
on: [workflow_dispatch]
permissions: { contents: read }
concurrency:
  group: production-deploy        # 그룹당 1개
  cancel-in-progress: false       # 배포는 취소 금지 (옳음) — 그러나...
jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production       # 🐛 승인 대기가 그룹을 점유합니다!
    steps: [{ run: echo deploying }]
EOF
gh api -X PUT "repos/{owner}/{repo}/environments/production" --input - <<EOF >/dev/null
{ "reviewers": [{ "type": "User", "id": $(gh api user -q .id) }], "prevent_self_review": true }
EOF
git add -A && git commit -qm "deploy with approval + concurrency" && git push -q

# 배포 3개를 연달아 트리거 (실제로는 머지 3건)
for i in 1 2 3; do gh workflow run deploy-stuck; sleep 10; done
sleep 30
gh run list --workflow=deploy-stuck --json status,displayTitle -q \
  '.[] | "\(.status)"' | sort | uniq -c
```

예상: 첫 런이 **waiting**(승인 대기)으로 `production-deploy` 그룹을 점유 — 뒤의 런들이 pending으로 줄줄이 대기. 승인자가 휴가면 이 줄은 영원합니다(카드 3의 증상). 진단·처방:

```bash
# 확인: waiting 런이 그룹을 잡고 있는가
gh run list --workflow=deploy-stuck --limit 5

# 처방(즉시): 막힌 런 취소로 줄 해소
for ID in $(gh run list --workflow=deploy-stuck --json databaseId -q '.[].databaseId'); do
  gh run cancel $ID 2>/dev/null || true
done
echo "재설계: 승인 대기 시한(environment의 wait timer와 별개로 자동 취소 정책) 또는"
echo "        승인을 concurrency 그룹 밖으로(승인 잡과 배포 잡 분리 — 승인은 그룹 미점유)"
```

✅ "그룹당 1개 + 취소 금지 + 사람 승인"의 **조합**이 데드락을 만듭니다 — 각각은 옳은 설정이라는 것이 이 카드의 함정(조합 리뷰가 필요한 이유).

## Step 3. 거짓 초록 재현 — 성공했는데 옛 버전 (카드 9)

```bash
# 로컬 도커로 최소 재현: latest 태그 재사용 + 캐시된 이미지
docker build -q -t fake-app:latest - <<'EOF'
FROM alpine
CMD ["echo", "version 1"]
EOF
docker run --rm fake-app:latest        # version 1

# "새 버전 배포" — 같은 태그로 다시 빌드했다고 치자 (다른 기계/레지스트리에서)
# 노드 입장: "fake-app:latest? 이미 있네" → pull 안 함 (IfNotPresent의 동작)
docker run --rm fake-app:latest        # 여전히 version 1 — 거짓 초록의 뿌리
```

파이프라인은 push까지 성공(초록)이지만, 노드는 캐시된 옛 이미지를 씁니다. 진단·처방:

```bash
# 확인 (카드 9): "실행 중인 것"의 다이제스트를 의도와 대조
docker inspect fake-app:latest --format '{{.Id}}' | cut -c1-19
echo "→ K8s라면: kubectl get pod -o jsonpath='{.status.containerStatuses[0].imageID}'"
echo "   이 다이제스트 vs 파이프라인이 push한 다이제스트를 대조 — 불일치면 확정"

# 처방: 다이제스트 배포 (04) + 배포 후 검증 스텝
cat <<'EOF'
deploy 잡의 마지막 스텝 (Knight의 교훈 — 24):
  kubectl rollout status deploy/app --timeout=120s
  RUNNING=$(kubectl get pod -l app=app -o jsonpath='{.items[0].status.containerStatuses[0].imageID}')
  [[ "$RUNNING" == *"$PUSHED_DIGEST"* ]] || { echo "🚨 배포됐다는데 다른 이미지가 돎"; exit 1; }
EOF
docker rmi fake-app:latest >/dev/null
```

✅ 성공의 정의를 바꿉니다: "apply 리턴 = 성공"이 아니라 **"의도한 다이제스트가 Ready = 성공"** — 거짓 초록 부류 전체에 대한 백신.

## Step 4. 산출물 — 오늘 밟은 진단 경로

```markdown
# 재현 → 카드 → 처방 기록
| 장애 | 카드 | 확인법 | 처방 | 예방 게이트 |
|------|------|--------|------|------------|
| 옛 의존성 재생 | 1 캐시 오염 | 캐시 무시 재실행 | 키에 hashFiles | 캐시 키 리뷰 정책(24) |
| 배포 줄 굳음 | 3 데드락 | waiting이 그룹 점유 확인 | 대기 취소+재설계 | 조합(승인+그룹) 리뷰 |
| 옛 버전이 돎 | 9 거짓 초록 | 실행 imageID vs 의도 다이제스트 | 다이제스트 배포+검증 스텝 | 성공의 재정의 |
```

## 정리

lab-02에서 이 저장소에 부러진 파이프라인 4종을 추가합니다. 유지.
