# Lab 01 — 페이즈 모델과 캐시 3종 실측

buildspec의 페이즈가 어떻게 실행되고 실패하는지, 캐시가 빌드 시간을 어떻게 바꾸는지 — 04의 원리가 CodeBuild 문법으로 재현되는 것을 봅니다.

```bash
export AWS_REGION=ap-northeast-2
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

## Step 1. 서비스 역할

```bash
cat > cb-trust.json <<'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codebuild.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name cb-lab-role --assume-role-policy-document file://cb-trust.json >/dev/null 2>&1 || true
BUCKET=cb-lab-cache-$ACCOUNT_ID
aws s3 mb s3://$BUCKET --region $AWS_REGION 2>/dev/null || true
aws iam put-role-policy --role-name cb-lab-role --policy-name inline --policy-document "{
  \"Version\":\"2012-10-17\",\"Statement\":[
    {\"Effect\":\"Allow\",\"Action\":[\"logs:*\"],\"Resource\":\"*\"},
    {\"Effect\":\"Allow\",\"Action\":[\"s3:*\"],\"Resource\":[\"arn:aws:s3:::$BUCKET\",\"arn:aws:s3:::$BUCKET/*\"]}
  ]}"
```

## Step 2. 페이즈 실패 동작을 buildspec으로

```bash
mkdir -p ~/ci-lab/cbuild && cd ~/ci-lab/cbuild
git init -q && git config user.email l@e.com && git config user.name L
cat > requirements.txt <<'EOF'
flask==3.1.0
requests==2.32.3
EOF
cat > buildspec.yml <<'EOF'
version: 0.2
phases:
  install:
    runtime-versions: { python: 3.12 }
    commands:
      - echo "[install] 런타임 준비"
  pre_build:
    commands:
      - echo "[pre_build] 의존성 설치 시작"
      - pip install -r requirements.txt
  build:
    commands:
      - echo "[build] 조리 중"
      - python -c "import flask; print('flask', flask.__version__)"
    finally:
      - echo "[build.finally] 성공이든 실패든 항상 실행 (Actions의 if:always)"
  post_build:
    commands:
      - echo "[post_build] 마무리"
cache:
  paths:
    - "/root/.cache/pip/**/*"        # ★ pip 캐시를 S3로 (04의 캐시 마운트 대응)
EOF
git add -A && git commit -qm "init" && git branch -M main
```

## Step 3. 프로젝트 생성 (S3 캐시 활성화)

```bash
aws codebuild create-project --region $AWS_REGION \
  --name cb-lab \
  --source "{\"type\":\"NO_SOURCE\",\"buildspec\":\"$(sed 's/"/\\"/g; s/$/\\n/' buildspec.yml | tr -d '\n')\"}" \
  --artifacts '{"type":"NO_ARTIFACTS"}' \
  --environment '{"type":"LINUX_CONTAINER","image":"aws/codebuild/amazonlinux2-x86_64-standard:5.0","computeType":"BUILD_GENERAL1_SMALL"}' \
  --cache "{\"type\":\"S3\",\"location\":\"$BUCKET/cache\"}" \
  --service-role arn:aws:iam::$ACCOUNT_ID:role/cb-lab-role >/dev/null 2>&1 || \
echo "(source 인라인이 복잡하면 GitHub 소스로 대체 — Step 3b)"
```

인라인 buildspec이 까다로우면 GitHub 소스로:

```bash
# Step 3b: GitHub 소스 버전
gh repo create cicd-lab-cbuild --public --source=. --push >/dev/null
REPO_URL="https://github.com/$(gh repo view --json nameWithOwner -q .nameWithOwner)"
aws codebuild update-project --region $AWS_REGION --name cb-lab \
  --source "{\"type\":\"GITHUB\",\"location\":\"$REPO_URL\"}" 2>/dev/null || \
aws codebuild create-project --region $AWS_REGION --name cb-lab \
  --source "{\"type\":\"GITHUB\",\"location\":\"$REPO_URL\"}" \
  --artifacts '{"type":"NO_ARTIFACTS"}' \
  --environment '{"type":"LINUX_CONTAINER","image":"aws/codebuild/amazonlinux2-x86_64-standard:5.0","computeType":"BUILD_GENERAL1_SMALL"}' \
  --cache "{\"type\":\"S3\",\"location\":\"$BUCKET/cache\"}" \
  --service-role arn:aws:iam::$ACCOUNT_ID:role/cb-lab-role >/dev/null
```

## Step 4. 첫 빌드 — 캐시 미스

```bash
BID=$(aws codebuild start-build --project-name cb-lab --region $AWS_REGION --query 'build.id' --output text)
echo "빌드: $BID — 완료 대기..."
while true; do
  ST=$(aws codebuild batch-get-builds --ids $BID --region $AWS_REGION --query 'builds[0].buildStatus' --output text)
  [ "$ST" != "IN_PROGRESS" ] && break; sleep 10
done
echo "상태: $ST"

# 페이즈별 소요 시간
aws codebuild batch-get-builds --ids $BID --region $AWS_REGION \
  --query 'builds[0].phases[].{phase:phaseType,sec:durationInSeconds,status:phaseStatus}' --output table
```

✅ `phases` 출력에서 install→pre_build→build→post_build의 순서와 각 소요를 봅니다. **pre_build(의존성 설치)가 가장 오래** 걸릴 것입니다.

## Step 5. 두 번째 빌드 — 캐시 히트

```bash
BID2=$(aws codebuild start-build --project-name cb-lab --region $AWS_REGION --query 'build.id' --output text)
while true; do
  ST=$(aws codebuild batch-get-builds --ids $BID2 --region $AWS_REGION --query 'builds[0].buildStatus' --output text)
  [ "$ST" != "IN_PROGRESS" ] && break; sleep 10
done
aws codebuild batch-get-builds --ids $BID2 --region $AWS_REGION \
  --query 'builds[0].phases[?phaseType==`PRE_BUILD` || phaseType==`DOWNLOAD_SOURCE`].{phase:phaseType,sec:durationInSeconds}' --output table
```

예상: 두 번째 빌드의 pre_build가 **더 빠릅니다** — S3 캐시(`/root/.cache/pip`)에서 휠을 복원했습니다. 04의 캐시 마운트가 CodeBuild에선 `cache.paths`로 표현된 것.

```markdown
# 캐시 효과 기록
| 빌드 | pre_build 시간 | 캐시 |
|------|--------------|------|
| 1차 | __초 | 미스 |
| 2차 | __초 | 히트 |
```

## Step 6. 페이즈 실패 실험

```bash
sed -i 's/pip install -r requirements.txt/pip install -r requirements.txt \&\& exit 1/' buildspec.yml
git commit -qam "test: fail pre_build" && git push -q 2>/dev/null || true

BID3=$(aws codebuild start-build --project-name cb-lab --region $AWS_REGION --query 'build.id' --output text)
while true; do
  ST=$(aws codebuild batch-get-builds --ids $BID3 --region $AWS_REGION --query 'builds[0].buildStatus' --output text)
  [ "$ST" != "IN_PROGRESS" ] && break; sleep 10
done
aws codebuild batch-get-builds --ids $BID3 --region $AWS_REGION \
  --query 'builds[0].phases[].{phase:phaseType,status:phaseStatus}' --output table
```

예상: pre_build가 `FAILED`, **build와 post_build는 실행되지 않음**(하지만 build의 `finally`는? — pre_build에서 죽었으므로 build 자체가 시작 안 됨). ✅ 페이즈 실패는 다음 페이즈를 막습니다. 되돌리기:

```bash
git revert --no-edit HEAD 2>/dev/null || sed -i 's/ && exit 1//' buildspec.yml
git commit -qam "revert" 2>/dev/null; git push -q 2>/dev/null || true
```

## Step 7. 산출물

```markdown
# CodeBuild 빌드 설계
- 페이즈: install(런타임) → pre_build(로그인/의존성) → build(컴파일/이미지) → post_build(푸시)
- finally: 정리·리포트 업로드 (성공/실패 무관) = Actions if:always
- 캐시: 의존성은 cache.paths(S3), Docker는 BuildKit+ECR 레지스트리 캐시(04)
- 실패 전파: 페이즈 실패 → 다음 중단. 정리는 finally에
- 시크릿: env.secrets-manager (평문 하드코딩 금지 — eks 25)
```

## 정리

프로젝트는 lab-02에서 VPC/배포로 확장.
