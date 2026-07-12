# Lab 02 — 승인 게이트, 권한 분리 검증, 그리고 선택

파이프라인에 수동 승인(01의 배포 버튼)을 넣고, IAM 분리가 실제로 격리하는지 확인한 뒤, Actions와의 선택 기준을 우리 맥락으로 정리합니다.

전제: lab-01의 파이프라인.

```bash
export AWS_REGION=ap-northeast-2
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
cd ~/ci-lab/codepipe
```

## Step 1. 수동 승인 스테이지 추가 (theory §1)

```bash
# SNS 토픽 (승인 알림)
TOPIC=$(aws sns create-topic --name cicd-lab-approvals --region $AWS_REGION --query TopicArn --output text)

# 현재 파이프라인을 가져와 Approval 스테이지 삽입
aws codepipeline get-pipeline --name cicd-lab-pipeline --region $AWS_REGION --query pipeline > pipe-cur.json

python3 - <<PY
import json
p = json.load(open("pipe-cur.json"))
p.pop("metadata", None)
p["stages"].append({
    "name": "Approval",
    "actions": [{
        "name": "ManualApproval",
        "actionTypeId": {"category":"Approval","owner":"AWS","provider":"Manual","version":"1"},
        "configuration": {"NotificationArn": "$TOPIC", "CustomData": "스테이징 검증 후 승인하세요"}
    }]
})
json.dump({"pipeline": p}, open("pipe-approval.json","w"), indent=2)
PY
aws codepipeline update-pipeline --cli-input-json file://pipe-approval.json --region $AWS_REGION >/dev/null
echo "승인 스테이지 추가됨"
```

## Step 2. 승인이 실제로 멈추는지

```bash
aws codepipeline start-pipeline-execution --name cicd-lab-pipeline --region $AWS_REGION >/dev/null
sleep 90
aws codepipeline get-pipeline-state --name cicd-lab-pipeline --region $AWS_REGION \
  --query 'stageStates[].{stage:stageName,status:latestExecution.status}' --output table
```

예상: Source·Build 완료, **Approval이 `InProgress`**(사람을 기다림). ✅ 01의 "Continuous Delivery: 배포 버튼은 사람이 누른다"의 AWS판.

승인:

```bash
TOKEN=$(aws codepipeline get-pipeline-state --name cicd-lab-pipeline --region $AWS_REGION \
  --query "stageStates[?stageName=='Approval'].actionStates[0].latestExecution.token" --output text)
aws codepipeline put-approval-result --region $AWS_REGION \
  --pipeline-name cicd-lab-pipeline --stage-name Approval --action-name ManualApproval \
  --result "summary=검증완료,status=Approved" \
  --token $TOKEN >/dev/null
echo "승인 완료"
```

## Step 3. IAM 분리 검증 — 빌드 역할로 배포를 시도하면?

theory §4의 분리가 진짜 격리인지 확인합니다:

```bash
# 빌드 역할이 가진 권한을 조회
aws iam get-role-policy --role-name cicd-lab-build --policy-name inline \
  --query 'PolicyDocument.Statement[].Action' --output json

# 빌드 역할을 assume해서 ECS 배포(가상)를 시도 — 권한이 없어야 합니다
CREDS=$(aws sts assume-role --role-arn arn:aws:iam::$ACCOUNT_ID:role/cicd-lab-build \
  --role-session-name test 2>/dev/null --query Credentials --output json) || echo "(assume 권한 없음 — 정상적일 수 있음)"
```

✅ **빌드 역할에는 배포 액션이 없습니다.** 빌드 컨테이너가 탈취돼도(공급망 공격) 배포 권한으로 번지지 않습니다 — 각 스테이지가 IAM 경계로 격리된 것이 Code 시리즈의 강점. 대가는 역할이 여러 개라는 복잡도.

## Step 4. 같은 목표를 GitHub Actions로 (비교)

같은 파이프라인(소스→빌드→승인)을 Actions로 표현하면:

```yaml
# 개념 비교 — 실제 구현은 03·06·07에서 했습니다
name: pipeline
on: { push: { branches: [main] } }
permissions: { id-token: write, contents: read }
jobs:
  build:
    runs-on: ubuntu-latest
    steps: [...]                    # CodeBuild 대신
  deploy-staging:
    needs: build
    environment: staging            # 06의 environment
    steps: [...]
  deploy-prod:
    needs: deploy-staging
    environment: production         # ★ 승인 = required reviewers (06)
    steps:
      - uses: aws-actions/configure-aws-credentials@v4   # OIDC (07)
```

비교표를 채웁니다:

```markdown
| 측면 | CodePipeline (방금) | GitHub Actions (06·07) |
|------|--------------------|-----------------------|
| 정의 위치 | AWS 리소스(CFN/CLI) | 저장소 안 YAML |
| 승인 | Manual approval + SNS | environment reviewers |
| 아티팩트 | S3(명시·감사) | outputs/artifacts(경량) |
| IAM | 파이프라인+액션 역할 분리 | OIDC role assume |
| PR 통합 | 약함(별도) | 강함(체크·코멘트) |
| 감사 | CloudTrail에 모든 것 | Actions 로그 |
| 상태 | 지속 리소스(콘솔에 늘 보임) | 실행마다 |
```

## Step 5. 선택 기준 — 우리 맥락으로 (산출물)

```markdown
# CI/CD 도구 선택 결정 (우리 조직)
## CI (빌드·테스트)
- 선택: GitHub Actions
- 근거: 개발자가 매일 보는 곳(PR 통합), 마켓플레이스 생태계, 04·05의 캐시·테스트 경험

## CD (배포)
- 선택: [ ] Actions+environments  [ ] CodePipeline  [ ] 혼용
- 판단 질문:
  1. 배포 대상이 AWS만인가요? (예 → 둘 다 가능)
  2. 규제/감사가 "모든 배포 액션이 CloudTrail에" 를 요구하나요? (예 → CodePipeline 가점)
  3. 배포 승인이 개발팀 밖(보안·운영)의 게이트인가요? (예 → CodePipeline의 조직 정책)
  4. IAM으로 스테이지별 경계를 명시해야 하나요? (예 → CodePipeline)
  5. 멀티클라우드 계획? (예 → Actions)

## 현실적 결론
- 대부분: CI=Actions, CD=Actions+environments(단순함)
- 규제 강한 프로덕션: CI=Actions, CD=CodePipeline(감사·승인 거버넌스)
- "우월한 도구"가 아니라 "맥락에 맞는 도구"
```

## Step 6. 중급 진도

```markdown
09 → CodePipeline: 오케스트레이션 철학과 IAM 분리      [ ]
→ 10(CodeBuild 심층), 11(CodeDeploy 배포 전략)로 Code 시리즈 완성
→ 12(GitLab CI), 13(Jenkins)로 생태계 전체 조망
```

## 정리

```bash
bash cleanup.sh
```
