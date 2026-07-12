# Lab 01 — GitLab 파이프라인을 Actions 지식으로 읽기

`.gitlab-ci.yml`을 작성하되, 각 부분을 Actions와 나란히 적어 **이식성**을 체득합니다. GitLab.com 무료 계정으로 실행하거나, 개념 대조로 진행합니다.

## Step 1. 프로젝트 (GitLab.com)

```bash
# GitLab CLI(glab) 또는 웹으로 프로젝트 생성
# glab auth login  후:
mkdir -p ~/ci-lab/glab && cd ~/ci-lab/glab
git init -q && git config user.email l@e.com && git config user.name L
cat > app.py <<'EOF'
def add(a, b): return a + b
EOF
cat > test_app.py <<'EOF'
from app import add
def test_add(): assert add(2, 3) == 5
EOF
git add -A && git commit -qm "init" && git branch -M main
# glab repo create cicd-lab-glab --public --push
# 또는 웹에서 프로젝트 만들고 remote 추가
```

## Step 2. 파이프라인 — Actions 대조를 주석으로

```bash
cat > .gitlab-ci.yml <<'EOF'
# ┌─────────────────────────────────────────────────────────┐
# │ GitLab CI              │ GitHub Actions 대응              │
# ├─────────────────────────────────────────────────────────┤
stages:                    # │ (Actions엔 없음 — needs로 순서)
  - lint
  - test
  - build

variables:                 # │ env: (워크플로 레벨)
  PY_IMAGE: python:3.12-slim

default:                   # │ 모든 잡 공통 (composite처럼)
  image: $PY_IMAGE

# ── lint 잡 ──            # │ jobs.lint
ruff:
  stage: lint              # │ (순서: lint stage가 먼저)
  script:                  # │ steps: - run:
    - pip install ruff
    - ruff check .

# ── test 잡 (매트릭스) ── # │ jobs.test + strategy.matrix
pytest:
  stage: test
  needs: [ruff]            # │ needs: [lint] — DAG (stage 안 기다리고 ruff 끝나면 바로)
  parallel:                # │ strategy.matrix
    matrix:
      - PY: ["3.11", "3.12", "3.13"]
  image: "python:$PY"
  script:
    - pip install pytest
    - pytest -q
  coverage: '/TOTAL.*\s(\d+%)$/'    # │ (Actions는 별도 액션 — 05의 diff 커버리지)

# ── build 잡 ──           # │ jobs.build
docker-build:
  stage: build
  rules:                   # │ if: github.ref == 'refs/heads/main'
    - if: '$CI_COMMIT_BRANCH == "main"'
  image: docker:27
  services: [ docker:27-dind ]   # │ services: (03의 service container)
  script:
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA .   # │ 내장 레지스트리! (04)
    - echo "GitLab 내장 레지스트리에 푸시 (Actions는 ECR/GHCR 별도)"
EOF
echo "작성 완료 — CI Lint로 검증 가능 (GitLab UI의 CI Lint)"
```

## Step 3. 대조표 완성 (산출물)

방금 쓴 파이프라인의 각 요소를 표로:

```markdown
# GitLab ↔ Actions 대조 (내가 만든 파이프라인 기준)
| 내가 쓴 것 | GitLab | Actions 등가물 |
|-----------|--------|---------------|
| 순서 정의 | stages: [lint,test,build] | needs: 체인 |
| 공통 이미지 | default.image | composite action / 각 job의 setup |
| DAG | needs: [ruff] | needs: [lint] |
| 매트릭스 | parallel.matrix | strategy.matrix |
| 브랜치 조건 | rules.if | if: github.ref |
| dind | services: docker:dind | services / 08의 dind |
| 레지스트리 | $CI_REGISTRY_IMAGE (내장) | ECR/GHCR (별도 구성) |
| 커버리지 | coverage: 정규식 | 별도 액션 + 05의 diff-cover |
```

✅ **가장 큰 차이 두 개**: ① GitLab은 stage가 1급 개념(Actions는 needs만) ② GitLab은 컨테이너 레지스트리가 내장(Actions는 외부 연결). 나머지는 표기 차이.

## Step 4. rules — Actions if보다 표현력이 큰 지점

GitLab의 `rules:`는 조건부 실행에서 더 강력합니다:

```bash
cat >> .gitlab-ci.yml <<'EOF'

# rules의 표현력 (Actions if로는 여러 줄 필요한 것)
smart-job:
  stage: test
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      when: always
    - if: '$CI_COMMIT_BRANCH == "main"'
      changes: [ "src/**/*" ]        # ★ 특정 경로 변경 시만 (06의 동적 매트릭스 씨앗)
      when: always
    - when: never                     # 그 외엔 실행 안 함
  script: [ "echo '조건부 실행'" ]
EOF
```

`changes:`는 경로 필터 — 20(모노레포)의 affected 빌드를 GitLab은 rules로 네이티브 지원합니다. Actions는 `dorny/paths-filter` 같은 액션이나 06의 동적 매트릭스로 구현.

## Step 5. 실행과 관찰 (GitLab.com이 있다면)

```bash
git add -A && git commit -qm "ci: gitlab pipeline"
# git push → 파이프라인 자동 실행
# GitLab UI → CI/CD → Pipelines에서 DAG 시각화 확인
echo "관찰 포인트:"
echo "  - stage 순서대로 진행되나, needs로 ruff→pytest가 build 대기 없이 병렬"
echo "  - 매트릭스가 pytest를 3개 잡으로 확장"
echo "  - main이 아니면 docker-build가 skip"
```

## 정리

lab-02에서 러너와 통합 기능을 다룹니다.
