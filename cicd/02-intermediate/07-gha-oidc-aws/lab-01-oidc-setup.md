# Lab 01 — 장기 키를 지우고 OIDC로 갈아타기

04에서 만든 빌드 워크플로를 그대로 가져와 **자격증명만 교체**합니다. 코드는 거의 그대로인데, 저장된 비밀이 사라집니다.

```bash
export AWS_REGION=ap-northeast-2
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

## Step 1. AWS에 GitHub을 신뢰할 발급자로 등록

계정당 한 번이면 됩니다(이미 있으면 건너뜀):

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --query 'OpenIDConnectProviderArn' --output text 2>/dev/null \
  || aws iam list-open-id-connect-providers \
       --query "OpenIDConnectProviderList[?contains(Arn,'token.actions.githubusercontent.com')].Arn" --output text
```

`--client-id-list sts.amazonaws.com`이 `aud` 값입니다 — theory §3의 빼면 안 되는 조건.

## Step 2. 저장소 준비 (04의 앱 재사용)

```bash
mkdir -p ~/ci-lab/oidc && cd ~/ci-lab/oidc
git init -q && git config user.email l@e.com && git config user.name L
printf 'module app\n\ngo 1.23\n' > go.mod
cat > main.go <<'EOF'
package main
import ("fmt"; "net/http")
func main() {
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) { fmt.Fprintln(w, "ok") })
    http.ListenAndServe(":8080", nil)
}
EOF
cat > Dockerfile <<'EOF'
FROM golang:1.23 AS build
WORKDIR /src
COPY go.mod ./
COPY . .
RUN CGO_ENABLED=0 go build -o /out/app .
FROM gcr.io/distroless/static:nonroot
COPY --from=build /out/app /app
USER nonroot:nonroot
ENTRYPOINT ["/app"]
EOF
echo -e ".git\n.github" > .dockerignore

git add -A && git commit -qm "init" && git branch -M main
gh repo create cicd-lab-oidc --public --source=. --push >/dev/null
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
echo "저장소: $REPO"
```

## Step 3. 역할 만들기 — 조건을 처음부터 좁게

```bash
aws ecr create-repository --repository-name cicd-oidc-app --region $AWS_REGION \
  --image-tag-mutability IMMUTABLE >/dev/null 2>&1 || true

cat > trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:$REPO:ref:refs/heads/main"
      }
    }
  }]
}
EOF
aws iam create-role --role-name gha-oidc-lab --assume-role-policy-document file://trust.json >/dev/null

# 인가는 별개 — 최소 권한 정책 (theory §7)
cat > policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "ecr:GetAuthorizationToken", "Resource": "*" },
    { "Effect": "Allow",
      "Action": ["ecr:BatchCheckLayerAvailability","ecr:CompleteLayerUpload","ecr:InitiateLayerUpload",
                 "ecr:PutImage","ecr:UploadLayerPart","ecr:BatchGetImage"],
      "Resource": "arn:aws:ecr:$AWS_REGION:$ACCOUNT_ID:repository/cicd-oidc-app" }
  ]
}
EOF
aws iam put-role-policy --role-name gha-oidc-lab --policy-name ecr-push --policy-document file://policy.json
echo "역할: arn:aws:iam::$ACCOUNT_ID:role/gha-oidc-lab"
```

✅ `sub`를 `ref:refs/heads/main`으로 못 박았습니다 — **PR에서는 이 역할을 얻을 수 없습니다.**

## Step 4. 워크플로 — 시크릿 없이

```bash
mkdir -p .github/workflows
cat > .github/workflows/build.yml <<EOF
name: build
on:
  push: { branches: [main] }
  pull_request:
  workflow_dispatch:

permissions:
  id-token: write      # ★ OIDC 토큰 요청 (기본은 없습니다)
  contents: read

env:
  AWS_REGION: $AWS_REGION
  ECR: $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/cicd-oidc-app
  ROLE: arn:aws:iam::$ACCOUNT_ID:role/gha-oidc-lab

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: 시크릿이 없음을 확인
        run: |
          if [ -z "\${{ secrets.AWS_ACCESS_KEY_ID }}" ]; then
            echo "✅ 저장된 AWS 키 없음"
          fi

      - name: OIDC로 역할 위임
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: \${{ env.ROLE }}
          aws-region: \${{ env.AWS_REGION }}
          role-session-name: gha-\${{ github.run_id }}    # CloudTrail 추적용

      - name: 나는 누구인가
        run: aws sts get-caller-identity

      - uses: docker/setup-buildx-action@v3
      - uses: aws-actions/amazon-ecr-login@v2

      - name: 빌드 & 푸시 (main에서만)
        if: github.ref == 'refs/heads/main'
        uses: docker/build-push-action@v6
        with:
          context: .
          push: true
          tags: \${{ env.ECR }}:\${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
EOF
git add -A && git commit -qm "ci: OIDC instead of long-lived keys" && git push -q
sleep 90
gh run view --log 2>/dev/null | grep -E "저장된 AWS 키 없음|Arn|assumed-role" | head -3
```

예상: `arn:aws:sts::<acct>:assumed-role/gha-oidc-lab/gha-<run_id>` — ✅ **저장된 비밀 없이** AWS에 인증했습니다.

## Step 5. 조건이 실제로 막는지 — PR에서 시도

```bash
git checkout -q -b feat/try-from-pr
echo "// change" >> main.go && git commit -qam "feat: change" && git push -qu origin feat/try-from-pr
gh pr create --title "PR에서 역할을 얻을 수 있나" --body "sub 조건 검증" --base main >/dev/null
sleep 70
gh run list --limit 1 --json headBranch,conclusion
gh run view --log-failed 2>/dev/null | grep -iE "not authorized|sts|assume" | head -2
```

예상: `configure-aws-credentials` 스텝에서 **실패** — `Not authorized to perform sts:AssumeRoleWithWebIdentity`. 이유: PR의 `sub`는 `repo:ORG/REPO:pull_request`이고, 신뢰 정책은 `ref:refs/heads/main`만 허용합니다.

✅ **IAM이 브랜치를 압니다.** 장기 키로는 표현할 수 없던 통제입니다. (PR에서도 AWS 읽기가 필요하다면 별도의 읽기 전용 역할과 별도의 `sub` 조건을 줍니다 — lab-02)

```bash
gh pr close --delete-branch 1 2>/dev/null || true
git checkout -q main
```

## Step 6. 토큰을 직접 들여다보기 (원리 확인)

```bash
cat > .github/workflows/inspect-token.yml <<'EOF'
name: inspect-token
on: workflow_dispatch
permissions: { id-token: write, contents: read }
jobs:
  peek:
    runs-on: ubuntu-latest
    steps:
      - name: OIDC 토큰의 클레임 (서명 제외, 값은 마스킹 주의)
        run: |
          TOKEN=$(curl -sH "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | jq -r .value)
          echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq '{iss, aud, sub, repository, ref, exp}'
EOF
git add -A && git commit -qm "ci: inspect oidc token" && git push -q
gh workflow run inspect-token.yml && sleep 35
gh run view --log 2>/dev/null | grep -A8 '"iss"' | head -10
```

예상 클레임:

```json
{ "iss": "https://token.actions.githubusercontent.com",
  "aud": "sts.amazonaws.com",
  "sub": "repo:you/cicd-lab-oidc:ref:refs/heads/main",
  "exp": 1770000000 }
```

✅ theory §1~2의 JWT를 눈으로 확인했습니다. `exp`가 몇 분 뒤임에 주목 — **훔쳐도 곧 쓸모없어집니다.**

## Step 7. 04의 부채 상환 확인

```markdown
# 자격증명 전환 체크리스트
- [x] IAM OIDC 제공자 등록 (계정당 1회, aud=sts.amazonaws.com)
- [x] 역할 + 신뢰 정책(sub를 브랜치까지 좁힘) + 최소권한 인가 정책
- [x] 워크플로: permissions.id-token: write + configure-aws-credentials
- [x] PR에서 역할 획득 실패 확인 (조건이 작동)
- [ ] **04의 AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY 시크릿 삭제**
- [ ] 그 액세스 키를 IAM에서 **비활성화 후 삭제** (시크릿만 지우면 키는 살아 있습니다!)
```

```bash
# 실제 프로젝트라면:
# gh secret delete AWS_ACCESS_KEY_ID; gh secret delete AWS_SECRET_ACCESS_KEY
# aws iam update-access-key --access-key-id AKIA... --status Inactive --user-name ci-user
# (며칠 관찰 후) aws iam delete-access-key --access-key-id AKIA... --user-name ci-user
```

## 정리

저장소·역할은 lab-02에서 계속 사용.
