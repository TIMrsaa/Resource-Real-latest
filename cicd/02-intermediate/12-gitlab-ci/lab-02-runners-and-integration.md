# Lab 02 — 러너, 내장 통합, DAG 파이프라인

GitLab의 Kubernetes executor(08 ARC 대응)와 통합 기능(리뷰앱·레지스트리)을 개념·구성으로 확인하고, 복잡한 파이프라인을 DAG로 구성합니다.

## Step 1. Kubernetes executor — 08의 ARC 대응

GitLab Runner를 EKS에 설치하면 잡마다 Pod를 만듭니다(ARC와 같은 사상):

```bash
# 개념 — GitLab Runner Helm 차트
cat <<'EOF'
# helm install gitlab-runner gitlab/gitlab-runner \
#   --set gitlabUrl=https://gitlab.com \
#   --set runnerRegistrationToken=<token> \
#   --set runners.executor=kubernetes \
#   --set runners.config="[[runners]]\n  [runners.kubernetes]\n    namespace = \"gitlab-runners\""
EOF

cat <<'EOF'
# ARC(08)와의 대응
| GitLab Runner (k8s executor) | GitHub ARC |
|------------------------------|------------|
| 잡마다 Pod                    | 잡마다 러너 Pod |
| namespace 격리               | arc-runners ns |
| Karpenter로 노드 확장(eks 17) | 동일 |
| ⚠️ 같은 함정: 퍼블릭 프로젝트 금지, ephemeral, IMDS 차단(08) |
EOF
```

✅ **도구가 달라도 위험은 이식됩니다** — 08에서 배운 self-hosted 러너 보안(퍼블릭 금지, egress 제한, IMDS hop limit)이 GitLab Runner에도 그대로 적용됩니다.

## Step 2. 러너 종류 — 신뢰 경계

```markdown
# GitLab 러너 스코프 (Actions와 비교)
| GitLab | 스코프 | Actions 등가 |
|--------|--------|-------------|
| Shared runner | 인스턴스 전체(GitLab.com 무료) | GitHub-hosted |
| Group runner | 그룹 내 프로젝트 | 조직 러너 |
| Specific/Project runner | 한 프로젝트 | 저장소 self-hosted |

# 보안 규율 (08의 이식)
- 신뢰할 수 없는(퍼블릭/포크) 파이프라인에 self-managed 러너 금지
- protected variables: protected 브랜치/태그에서만 노출 (06의 environment secret 대응)
- masked variables: 로그 마스킹 (03의 시크릿 마스킹, 인코딩 우회 주의)
```

## Step 3. 내장 레지스트리 — 통합의 실물

GitLab은 컨테이너 레지스트리가 내장입니다(theory §4). Actions/ECR과 비교:

```markdown
# 이미지 흐름 비교
GitLab:  build → $CI_REGISTRY_IMAGE (같은 플랫폼, 자동 인증)
Actions: build → ECR/GHCR (07 OIDC로 인증, 별도 구성)

# 트레이드오프
GitLab: 매끄러움(인증·권한이 프로젝트와 통합) ↔ 벤더 종속
Actions+ECR: 유연(어느 레지스트리든) ↔ 조립 필요
```

$CI_REGISTRY_IMAGE에 푸시하면 GitLab이 자동으로 인증을 처리합니다 — 04에서 우리가 ECR 로그인·OIDC로 조립한 것을 GitLab은 내장으로 줍니다. 대가는 그 레지스트리를 벗어나기 어렵다는 것.

## Step 4. 리뷰앱 — GitLab만의 강점 (개념)

MR마다 임시 환경을 자동 생성:

```yaml
review:
  stage: deploy
  script:
    - kubectl create ns review-$CI_MERGE_REQUEST_IID
    - helm install review-$CI_MERGE_REQUEST_IID ./chart --set image=$IMAGE
  environment:
    name: review/$CI_MERGE_REQUEST_IID
    url: https://$CI_MERGE_REQUEST_IID.review.example.com
    on_stop: stop-review          # MR 닫히면 자동 정리
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'

stop-review:
  stage: deploy
  script: [ "kubectl delete ns review-$CI_MERGE_REQUEST_IID" ]
  environment: { name: review/$CI_MERGE_REQUEST_IID, action: stop }
  when: manual
```

✅ **리뷰어가 코드가 아니라 실제 동작을 보고 리뷰합니다** — 02에서 "리뷰 대기가 리드 타임의 병목"이라 했는데, 리뷰앱은 리뷰의 질을 높여 재작업을 줄입니다. Actions로도 가능하지만 여러 조각을 조립해야 하는 것을 GitLab은 `environment.on_stop`으로 내장합니다.

## Step 5. DAG로 복잡한 흐름 (06의 동적 매트릭스 대응)

```bash
cd ~/ci-lab/glab
cat > .gitlab-ci-dag.yml <<'EOF'
stages: [prepare, build, test, deploy]

# stage 순서를 무시하고 needs로 최적 병렬 (DAG)
prepare-a: { stage: prepare, script: ["echo A"] }
prepare-b: { stage: prepare, script: ["echo B"] }

build-x:
  stage: build
  needs: [prepare-a]        # prepare-b를 안 기다립니다!
  script: ["echo build X"]

build-y:
  stage: build
  needs: [prepare-b]
  script: ["echo build Y"]

test-x:
  stage: test
  needs: [build-x]          # build-y 무관
  script: ["echo test X"]

deploy:
  stage: deploy
  needs: [test-x, build-y]  # 둘 다 필요
  script: ["echo deploy"]
EOF
echo "DAG: needs가 stage 순서를 건너뛰어 최단 경로로 병렬 실행"
echo "→ Actions의 needs와 동일 개념, GitLab은 stage와 needs를 함께 씀"
```

✅ stage(기본 순서)와 needs(DAG)의 조합이 GitLab의 파이프라인 표현력입니다. Actions는 stage가 없어 needs만으로 전부 표현합니다 — 같은 DAG를 다른 어휘로.

## Step 6. 산출물 — 도구 독립적 CI 이해

```markdown
# CI 도구 이식성 체크리스트 (내가 확인한 것)
- [ ] 스테이지/잡/스텝의 개념이 도구 간 이식됨을 확인
- [ ] 러너 모델(hosted vs self, executor)과 그 보안 함정이 동일함(08)
- [ ] 캐시 키 원리(04), 시크릿 마스킹(03), OIDC(07)가 이식됨
- [ ] 진짜 차이는 문법이 아니라 철학(통합 vs 조합)과 1급 개념(stage)

# 다음 도구를 만나면 (Tekton 16, Jenkins 13, ...)
1. "잡/스텝/러너/아티팩트/시크릿"이 무엇에 해당하나 먼저 매핑
2. 그 도구만의 1급 개념이 뭔가 (GitLab=stage, Tekton=Task/Pipeline CRD)
3. 철학이 뭔가 (통합? 조합? 클라우드 네이티브?)
→ 이 세 질문이면 어떤 CI든 하루면 읽습니다
```

## Step 7. 중급 진도

```markdown
12 → GitLab CI: 개념 이식성 + 통합 철학              [ ]
→ 13(Jenkins): 가장 오래된 도구, 플러그인 생태계, "왜 아직 쓰나"
→ 고급(14~15): GitOps로 배포 패러다임이 바뀝니다(push→pull)
```

## 정리

```bash
bash cleanup.sh
```
