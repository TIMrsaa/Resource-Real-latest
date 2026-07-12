# Lab 02 — Actions에서 빌드하고 ECR로 밀기

lab-01의 이해를 CI로 옮깁니다: 러너의 빈 캐시를 외부 백엔드로 채우고, 불변 태그로 푸시하고, **다이제스트를 출력**해 이후 배포 단계가 그것을 쓰게 합니다.

```bash
export AWS_REGION=ap-northeast-2
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

## Step 1. ECR 리포지토리 — 태그 불변성을 켭니다

```bash
aws ecr create-repository --repository-name cicd-lab-app --region $AWS_REGION \
  --image-tag-mutability IMMUTABLE \
  --image-scanning-configuration scanOnPush=true \
  --query 'repository.repositoryUri' --output text
```

`IMMUTABLE`: 같은 태그로 재푸시하면 **거부**됩니다 — 실수로 태그를 움직이는 것을 레지스트리가 막습니다(theory §5). `scanOnPush`: 푸시할 때마다 취약점 스캔(21에서 게이트로 승격).

## Step 2. 저장소와 앱

```bash
mkdir -p ~/ci-lab/buildci && cd ~/ci-lab/buildci
git init -q && git config user.email l@e.com && git config user.name L

cat > main.go <<'EOF'
package main

import ("fmt"; "net/http"; "os")

func main() {
    v := os.Getenv("APP_VERSION")
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "hello %s\n", v)
    })
    http.ListenAndServe(":8080", nil)
}
EOF
printf 'module app\n\ngo 1.23\n' > go.mod

cat > Dockerfile <<'EOF'
# syntax=docker/dockerfile:1
FROM golang:1.23 AS build
WORKDIR /src
COPY go.mod ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -o /out/app .

FROM gcr.io/distroless/static:nonroot
COPY --from=build /out/app /app
USER nonroot:nonroot
ENTRYPOINT ["/app"]
EOF

cat > .dockerignore <<'EOF'
.git
.github
EOF

git add -A && git commit -qm "init" && git branch -M main
gh repo create cicd-lab-build --private --source=. --push
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

## Step 3. 자격증명 — 지금은 키, 07에서 OIDC로

```bash
# ⚠️ 임시: 장기 액세스 키를 시크릿에. 07에서 이것을 제거하는 것이 목표입니다.
gh secret set AWS_ACCESS_KEY_ID --body "$(aws configure get aws_access_key_id)"
gh secret set AWS_SECRET_ACCESS_KEY --body "$(aws configure get aws_secret_access_key)"
gh variable set AWS_REGION --body "$AWS_REGION"
gh variable set ECR_REPOSITORY --body "$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cicd-lab-app"
```

> 이 랩이 끝나면 이 키를 지웁니다. **장기 키를 CI에 두는 것은 07에서 없앨 부채**입니다 — 유출 시 회전 외에 방법이 없고, 03의 사고 사례가 정확히 이 유형이었습니다.

## Step 4. 빌드·푸시 워크플로

```bash
mkdir -p .github/workflows
cat > .github/workflows/build.yml <<'EOF'
name: build

on:
  push:
    branches: [main]

concurrency:
  group: build-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    outputs:
      digest: ${{ steps.push.outputs.digest }}     # ★ 이후 배포가 쓸 값 (03의 outputs)
    steps:
      - uses: actions/checkout@v4

      - uses: docker/setup-buildx-action@v3        # BuildKit 빌더

      - name: ECR 로그인
        uses: aws-actions/amazon-ecr-login@v2
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          AWS_REGION: ${{ vars.AWS_REGION }}

      - name: 태그 결정 (불변)
        id: meta
        run: echo "tag=${{ vars.ECR_REPOSITORY }}:${GITHUB_SHA::12}" >> "$GITHUB_OUTPUT"

      - name: 빌드 & 푸시
        id: push
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tag }}
          cache-from: |
            type=gha
            type=gha,scope=main
          cache-to: type=gha,mode=max,scope=${{ github.ref_name }}

      - name: 다이제스트 출력 — 배포는 이것으로
        run: |
          echo "tag    : ${{ steps.meta.outputs.tag }}"
          echo "digest : ${{ steps.push.outputs.digest }}"
          echo "배포 참조: ${{ vars.ECR_REPOSITORY }}@${{ steps.push.outputs.digest }}"
EOF
git add -A && git commit -qm "ci: build and push to ECR" && git push -q
```

## Step 5. 실행 — 콜드 캐시 vs 웜 캐시

```bash
sleep 90
gh run list --workflow=build --limit 1
gh run view --log 2>/dev/null | grep -E "digest|배포 참조" | head -3

# 코드만 바꾸고 재실행 (의존성 레이어는 캐시 히트해야 합니다)
sed -i 's/hello %s/hi %s/' main.go
git commit -qam "feat: change greeting" && git push -q
sleep 90

gh run list --workflow=build --limit 2 --json databaseId,createdAt,updatedAt \
  --jq '.[] | {run: .databaseId, sec: (((.updatedAt|fromdate)-(.createdAt|fromdate)))}'
```

예상: 2차 실행이 **눈에 띄게 빠릅니다** — `cache-from: type=gha`가 lab-01의 레이어·캐시 마운트를 복원했습니다. 로그에서 `CACHED` 라인을 세어보세요:

```bash
gh run view --log 2>/dev/null | grep -c "CACHED" || true
```

## Step 6. 불변성이 실제로 강제되는지

```bash
# 같은 커밋(같은 태그)으로 재푸시를 시도하면?
gh workflow run build.yml --ref main
sleep 80
gh run view --log-failed 2>/dev/null | grep -i "immutable\|already exists" | head -2 \
  || echo "(같은 다이제스트면 ECR이 no-op으로 처리하기도 합니다 — 내용이 다를 때 거부됩니다)"
```

✅ 태그 불변성은 "테스트한 이미지와 배포되는 이미지가 같다"를 **레지스트리 수준에서** 보증합니다 — 01의 아티팩트 불변성 원칙에 물리적 실체를 줍니다.

## Step 7. 다이제스트로 배포하는 매니페스트 (미리보기)

```bash
DIGEST=$(aws ecr describe-images --repository-name cicd-lab-app --region $AWS_REGION \
  --query 'sort_by(imageDetails,&imagePushedAt)[-1].imageDigest' --output text)
echo "최신 다이제스트: $DIGEST"

cat <<EOF
# 배포 매니페스트는 이렇게 참조합니다 (09~11, 14~15에서 자동화)
    image: $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cicd-lab-app@$DIGEST
# 태그(:abc123)가 아니라 다이제스트(@sha256:...) — 태그는 움직일 수 있습니다
EOF
```

## Step 8. 산출물 — 빌드 워크플로 규칙

```markdown
# 이미지 빌드 규칙
- 태그: `<ecr>/<app>:<git-sha 12자>` (불변, 커밋과 1:1)
- ECR: IMMUTABLE + scanOnPush (21에서 스캔을 게이트로)
- 배포 참조: **다이제스트**. 태그는 사람용 별명
- 캐시: type=gha, mode=max + main 스코프 폴백 (새 브랜치도 웜 스타트)
- Dockerfile: 멀티스테이지 + distroless + nonroot + 시크릿 마운트
- 부채: 장기 AWS 키 → **07에서 OIDC로 제거** (기한: 07 완료 시)
```

## 정리

```bash
bash cleanup.sh
```
