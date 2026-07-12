# Lab 02 — 조건의 구멍을 열어보고, 환경으로 잠그기

OIDC는 켜기 쉽습니다. 위험한 것은 신뢰 정책입니다. 이 랩은 **와일드카드 조건이 만드는 침해 경로를 직접 재현**하고, environment(06)로 프로덕션을 잠급니다.

```bash
cd ~/ci-lab/oidc
export AWS_REGION=ap-northeast-2
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
OWNER=$(echo $REPO | cut -d/ -f1)
```

## Step 1. 구멍을 엽니다 — `repo:OWNER/*:*`

실무에서 흔히 보는 "일단 되게 하자" 조건:

```bash
cat > trust-wide.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike":   { "token.actions.githubusercontent.com:sub": "repo:$OWNER/*:*" }
    }
  }]
}
EOF
aws iam update-assume-role-policy --role-name gha-oidc-lab --policy-document file://trust-wide.json
echo "⚠️ 조건을 org 전체로 넓혔다"
```

## Step 2. 침해 재현 — 전혀 무관한 저장소에서 그 역할을 얻습니다

```bash
mkdir -p ~/ci-lab/attacker/.github/workflows && cd ~/ci-lab/attacker
git init -q && git config user.email l@e.com && git config user.name L
cat > .github/workflows/steal.yml <<EOF
name: unrelated-repo
on: [push, workflow_dispatch]
permissions: { id-token: write, contents: read }
jobs:
  demo:
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::$ACCOUNT_ID:role/gha-oidc-lab
          aws-region: $AWS_REGION
      - name: 나는 이 역할과 아무 관계 없는 저장소입니다
        run: |
          aws sts get-caller-identity
          aws ecr describe-repositories --region $AWS_REGION --query 'repositories[].repositoryName' || true
EOF
echo "# unrelated" > README.md
git add -A && git commit -qm "unrelated repo" && git branch -M main
gh repo create cicd-lab-unrelated --public --source=. --push >/dev/null
sleep 70
gh run view --log 2>/dev/null | grep -E "Arn|assumed-role" | head -2
```

예상: **성공합니다.** 전혀 다른 저장소가 그 역할을 얻었습니다.

✅ 이것이 `repo:org/*:*`의 의미입니다: 조직의 **누구든, 어떤 저장소든, 어떤 브랜치든**(인턴의 테스트 저장소도, 실수로 만든 퍼블릭 저장소도) 그 역할과 그 역할이 가진 모든 권한을 얻습니다. 그리고 조직에 저장소를 만들 수 있는 사람은 대개 많습니다.

## Step 3. 구멍을 닫습니다 — 정확한 `sub`로

```bash
cd ~/ci-lab/oidc
aws iam update-assume-role-policy --role-name gha-oidc-lab --policy-document file://trust.json   # lab-01의 좁은 조건

cd ~/ci-lab/attacker
gh workflow run steal.yml && sleep 45
gh run view --log-failed 2>/dev/null | grep -iE "not authorized" | head -1 && echo "✅ 차단됨"
```

## Step 4. 환경별 역할 — 프로덕션은 승인된 배포에서만

06의 environment와 결합합니다. `sub`가 `environment:` 형태로 **대체**된다는 것(theory §2)이 핵심.

```bash
cd ~/ci-lab/oidc

# 환경 생성 (production은 승인 필요)
gh api -X PUT "repos/$REPO/environments/staging" >/dev/null
ME=$(gh api user -q .id)
gh api -X PUT "repos/$REPO/environments/production" \
  -F "reviewers[][type]=User" -F "reviewers[][id]=$ME" \
  -F "deployment_branch_policy[protected_branches]=true" \
  -F "deployment_branch_policy[custom_branch_policies]=false" >/dev/null

# 역할 두 개: staging(읽기+푸시), production(승인된 배포에서만)
for ENV in staging production; do
cat > trust-$ENV.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
        "token.actions.githubusercontent.com:sub": "repo:$REPO:environment:$ENV"
      }
    }
  }]
}
EOF
aws iam create-role --role-name gha-$ENV-lab --assume-role-policy-document file://trust-$ENV.json >/dev/null 2>&1 || \
aws iam update-assume-role-policy --role-name gha-$ENV-lab --policy-document file://trust-$ENV.json
aws iam put-role-policy --role-name gha-$ENV-lab --policy-name read-ecr --policy-document '{
  "Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["ecr:DescribeRepositories","ecr:GetAuthorizationToken"],"Resource":"*"}]}'
done
echo "역할 2개 생성"
```

## Step 5. 승격 파이프라인 — 각 단계가 자기 역할을 얻습니다

```bash
cat > .github/workflows/deploy.yml <<EOF
name: deploy
on:
  push: { branches: [main] }
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  staging:
    environment: staging                    # ★ sub = repo:...:environment:staging
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::$ACCOUNT_ID:role/gha-staging-lab
          aws-region: $AWS_REGION
          role-session-name: staging-\${{ github.run_id }}
      - run: aws sts get-caller-identity --query Arn --output text

  production:
    needs: staging
    environment: production                 # ★ 승인 후에만 이 sub를 갖습니다
    runs-on: ubuntu-latest
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::$ACCOUNT_ID:role/gha-production-lab
          aws-region: $AWS_REGION
          role-session-name: prod-\${{ github.run_id }}
      - run: aws sts get-caller-identity --query Arn --output text

  # 통제 검증: staging 잡이 production 역할을 훔칠 수 있나요?
  cross-role-attempt:
    environment: staging
    runs-on: ubuntu-latest
    continue-on-error: true
    steps:
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::$ACCOUNT_ID:role/gha-production-lab   # 🚨 시도
          aws-region: $AWS_REGION
      - run: echo "이 줄이 보이면 통제 실패"
EOF
git add -A && git commit -qm "ci: environment-scoped OIDC roles" && git push -q
sleep 80
gh run view --json jobs -q '.jobs[] | {name, conclusion, status}' 2>/dev/null
```

예상:

- `staging`: 성공 (`assumed-role/gha-staging-lab/...`)
- `cross-role-attempt`: **실패** — staging 환경의 `sub`로는 production 역할의 조건을 만족하지 못합니다
- `production`: **waiting** (승인 대기)

✅ **IAM 조건과 GitHub 환경 승인이 하나의 통제로 맞물립니다.** 워크플로 파일을 고칠 수 있는 사람도 production 역할을 훔칠 수 없습니다 — 그러려면 승인을 받아야 하고, 승인은 저장소 설정이 강제합니다.

승인해서 마무리:

```bash
RUN_ID=$(gh run list --workflow=deploy --limit 1 --json databaseId -q '.[0].databaseId')
ENV_ID=$(gh api "repos/$REPO/environments/production" -q .id)
gh api -X POST "repos/$REPO/actions/runs/$RUN_ID/pending_deployments" \
  -F "environment_ids[]=$ENV_ID" -f state=approved -f comment="검증 완료" >/dev/null
sleep 30
gh run view $RUN_ID --log 2>/dev/null | grep "assumed-role" | tail -1
```

## Step 6. 감사 — CloudTrail에서 역추적

```bash
sleep 60   # CloudTrail 전파
aws cloudtrail lookup-events --region $AWS_REGION \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 3 \
  --query 'Events[].{time:EventTime,user:Username}' --output table 2>/dev/null || echo "(전파 대기 또는 CloudTrail 미설정)"
```

`role-session-name`에 run_id를 넣었으므로 — CloudTrail의 세션 이름에서 **어느 워크플로 실행이 어떤 API를 호출했는지** 역추적됩니다(eks 25의 감사 사고방식).

## Step 7. 산출물 — 역할 매트릭스

```markdown
# OIDC 역할 설계
| 역할 | sub 조건 | 권한 | 획득 가능 시점 |
|------|---------|------|--------------|
| gha-ci-read | repo:ORG/APP:pull_request | ECR 읽기 | 모든 PR |
| gha-staging | repo:ORG/APP:environment:staging | 배포(스테이징) | main push |
| gha-production | repo:ORG/APP:environment:production | 배포(프로덕션) | **승인 후에만** |

## 규칙
- `aud: sts.amazonaws.com` 조건 필수
- 와일드카드 `repo:ORG/*:*` 금지 — 조직의 모든 저장소가 그 역할을 얻습니다(Step 2에서 재현)
- OIDC는 인증일 뿐 — 각 역할의 **인가 정책도 최소권한**(theory §7)
- role-session-name에 `${{ github.repository }}-${{ github.run_id }}` → CloudTrail 추적
- 장기 키 잔재: IAM에서 비활성화 → 관찰 → 삭제 (시크릿 삭제만으로는 키가 살아 있습니다)
```

## 정리

```bash
bash cleanup.sh
```
