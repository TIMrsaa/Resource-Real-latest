# Lab 01 — Connection·스테이지·아티팩트 흐름

CodePipeline을 CloudFormation으로 세웁니다(콘솔 클릭 대신 — theory §5). GitHub 소스 → CodeBuild → 아티팩트가 S3를 흐르는 것을 눈으로 확인합니다.

```bash
export AWS_REGION=ap-northeast-2
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

## Step 1. 소스 저장소

```bash
mkdir -p ~/ci-lab/codepipe && cd ~/ci-lab/codepipe
git init -q && git config user.email l@e.com && git config user.name L
cat > buildspec.yml <<'EOF'
version: 0.2
phases:
  build:
    commands:
      - echo "빌드 중 — 소스가 여기 도착했다"
      - ls -la
      - echo "artifact-$(date +%s)" > build-output.txt
artifacts:
  files:
    - build-output.txt          # ★ 이 파일이 BuildArtifact가 되어 다음 스테이지로
EOF
echo "print('hello')" > app.py
git add -A && git commit -qm "init" && git branch -M main
gh repo create cicd-lab-codepipe --public --source=. --push >/dev/null
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

## Step 2. CodeStar Connection — GitHub 접합 (PAT 없이)

```bash
CONN_ARN=$(aws codeconnections create-connection \
  --provider-type GitHub --connection-name cicd-lab-conn \
  --region $AWS_REGION --query ConnectionArn --output text)
echo "Connection: $CONN_ARN"

# PENDING 상태 — 콘솔에서 GitHub OAuth 승인 필요 (한 번)
aws codeconnections get-connection --connection-arn $CONN_ARN --region $AWS_REGION \
  --query 'Connection.ConnectionStatus' --output text
echo "→ 콘솔에서 승인: https://console.aws.amazon.com/codesuite/settings/connections"
echo "   Pending 연결을 'Update pending connection'으로 GitHub 인증 후 계속"
read -p "AVAILABLE이 되면 Enter..." _
```

✅ Connection은 GitHub App 기반 — 파이프라인에 GitHub 토큰을 저장하지 않습니다(07의 사상).

## Step 3. IAM 역할 두 개 (theory §4의 분리)

```bash
# 아티팩트 버킷
BUCKET=cicd-lab-artifacts-$ACCOUNT_ID
aws s3 mb s3://$BUCKET --region $AWS_REGION

# ① 파이프라인 서비스 역할
cat > pipe-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codepipeline.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name cicd-lab-pipeline --assume-role-policy-document file://pipe-trust.json >/dev/null
aws iam put-role-policy --role-name cicd-lab-pipeline --policy-name inline --policy-document "{
  \"Version\":\"2012-10-17\",\"Statement\":[
    {\"Effect\":\"Allow\",\"Action\":[\"s3:*\"],\"Resource\":[\"arn:aws:s3:::$BUCKET\",\"arn:aws:s3:::$BUCKET/*\"]},
    {\"Effect\":\"Allow\",\"Action\":[\"codebuild:StartBuild\",\"codebuild:BatchGetBuilds\"],\"Resource\":\"*\"},
    {\"Effect\":\"Allow\",\"Action\":[\"codeconnections:UseConnection\"],\"Resource\":\"$CONN_ARN\"}
  ]}"

# ② CodeBuild 서비스 역할 (빌드가 하는 일만)
cat > build-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codebuild.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name cicd-lab-build --assume-role-policy-document file://build-trust.json >/dev/null
aws iam put-role-policy --role-name cicd-lab-build --policy-name inline --policy-document "{
  \"Version\":\"2012-10-17\",\"Statement\":[
    {\"Effect\":\"Allow\",\"Action\":[\"logs:CreateLogGroup\",\"logs:CreateLogStream\",\"logs:PutLogEvents\"],\"Resource\":\"*\"},
    {\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\",\"s3:PutObject\"],\"Resource\":\"arn:aws:s3:::$BUCKET/*\"}
  ]}"
```

✅ **빌드 역할에 배포 권한이 없습니다** — 각 액션은 자기 일의 권한만. theory §4의 분리가 실물로.

## Step 4. CodeBuild 프로젝트

```bash
aws codebuild create-project --region $AWS_REGION \
  --name cicd-lab-build \
  --source '{"type":"CODEPIPELINE"}' \
  --artifacts '{"type":"CODEPIPELINE"}' \
  --environment '{"type":"LINUX_CONTAINER","image":"aws/codebuild/amazonlinux2-x86_64-standard:5.0","computeType":"BUILD_GENERAL1_SMALL"}' \
  --service-role arn:aws:iam::$ACCOUNT_ID:role/cicd-lab-build >/dev/null
echo "CodeBuild 프로젝트 생성"
```

`source: CODEPIPELINE`이 핵심 — 소스를 파이프라인이 아티팩트로 넘겨준다는 뜻.

## Step 5. 파이프라인 — 스테이지를 엮습니다

```bash
cat > pipeline.json <<EOF
{
  "pipeline": {
    "name": "cicd-lab-pipeline",
    "roleArn": "arn:aws:iam::$ACCOUNT_ID:role/cicd-lab-pipeline",
    "artifactStore": { "type": "S3", "location": "$BUCKET" },
    "pipelineType": "V2",
    "stages": [
      {
        "name": "Source",
        "actions": [{
          "name": "GitHub",
          "actionTypeId": {"category":"Source","owner":"AWS","provider":"CodeStarSourceConnection","version":"1"},
          "configuration": {
            "ConnectionArn": "$CONN_ARN",
            "FullRepositoryId": "$REPO",
            "BranchName": "main",
            "OutputArtifactFormat": "CODE_ZIP"
          },
          "outputArtifacts": [{"name":"SourceArtifact"}]
        }]
      },
      {
        "name": "Build",
        "actions": [{
          "name": "Build",
          "actionTypeId": {"category":"Build","owner":"AWS","provider":"CodeBuild","version":"1"},
          "configuration": {"ProjectName":"cicd-lab-build"},
          "inputArtifacts": [{"name":"SourceArtifact"}],
          "outputArtifacts": [{"name":"BuildArtifact"}]
        }]
      }
    ]
  }
}
EOF
aws codepipeline create-pipeline --cli-input-json file://pipeline.json --region $AWS_REGION >/dev/null
echo "파이프라인 생성 — 자동 실행 시작"
```

## Step 6. 아티팩트 흐름 관찰

```bash
sleep 60
aws codepipeline get-pipeline-state --name cicd-lab-pipeline --region $AWS_REGION \
  --query 'stageStates[].{stage:stageName,status:latestExecution.status}' --output table

# S3 아티팩트 버킷에 무엇이 담겼나 (theory §2)
aws s3 ls s3://$BUCKET/cicd-lab-pipeline/ --recursive | head
```

예상: Source·Build 스테이지가 `Succeeded`, S3에 `SourceArti/`와 `BuildArtif/` zip들. ✅ **각 스테이지의 산출물이 S3에 명시적으로 보관**됩니다 — Actions의 암묵적 전달과 다른, 감사 가능한 흐름.

빌드 로그 확인:

```bash
BUILD_ID=$(aws codebuild list-builds-for-project --project-name cicd-lab-build --region $AWS_REGION --query 'ids[0]' --output text)
aws logs tail /aws/codebuild/cicd-lab-build --region $AWS_REGION --since 5m 2>/dev/null | grep -E "빌드 중|artifact" | head
```

## Step 7. 자동 트리거 — push가 파이프라인을 시작

```bash
echo "# trigger" >> app.py
git commit -qam "feat: trigger pipeline" && git push -q
sleep 30
aws codepipeline list-pipeline-executions --pipeline-name cicd-lab-pipeline --region $AWS_REGION \
  --query 'pipelineExecutionSummaries[0].{status:status,trigger:trigger.triggerType}' --output json
```

✅ Connection의 웹훅이 push를 감지해 파이프라인을 자동 시작했습니다.

## 정리

파이프라인은 lab-02에서 계속 사용.
