# 이론 — 개념 매핑, 러너 모델, 통합 철학

> **🌱 17세 눈높이 비유: 같은 요리, 다른 나라 레시피북**
> 김치찌개를 만드는 법은 나라마다 표기가 다릅니다 — "돼지고기 200g"이 어떤 책은 "pork 7oz", 어떤 책은 그림으로. 하지만 **요리 자체는 같습니다.** CI 도구도 그렇습니다: GitHub은 `jobs:`, GitLab은 `stages:`+`jobs`, 젠킨스는 `stage()` — 표기만 다르고 "빌드→테스트→배포"라는 요리는 같습니다. 요리를 알면 어떤 레시피북이든 읽습니다.

---

## 1. 개념 매핑표 (이 모듈의 핵심)

| 개념 | GitHub Actions | GitLab CI | 비고 |
|------|---------------|-----------|------|
| 파이프라인 트리거 | `on:` | `workflow:` / `rules:` | |
| 실행 단위 | job | job | GitLab job은 `stage`에 속함 |
| 순서 | `needs:` | `stage` 순서 + `needs:`(DAG) | GitLab은 stage가 기본 순서 |
| 병렬 | 기본 병렬 | 같은 stage 내 병렬 | |
| 매트릭스 | `strategy.matrix` | `parallel.matrix` | 거의 동일 |
| 조건 | `if:` | `rules:` | rules가 더 표현력 큼 |
| 재사용 | reusable workflow | `include:` + `extends` | |
| 아티팩트 | upload/download-artifact | `artifacts:` | GitLab은 job 간 자동 전달 |
| 캐시 | `actions/cache` | `cache:` | 개념 동일(04의 키 원리) |
| 시크릿 | secrets | CI/CD variables (masked/protected) | |
| 환경 | environments | environments | 둘 다 승인·배포 추적 |
| OIDC | id-token | `id_tokens` | 07과 동일 원리 |

**읽는 법**: GitLab YAML을 만나면 이 표의 오른쪽에서 왼쪽으로 번역해 이해하세요. 90%가 이 표로 커버됩니다.

## 2. `.gitlab-ci.yml` 구조

```yaml
stages: [build, test, deploy]          # 순서 정의 (Actions엔 없는 개념)

variables:
  IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA   # 내장 변수 (04의 불변 태그)

build:
  stage: build
  script: [ "docker build -t $IMAGE ." ]
  cache:
    key: { files: [package-lock.json] }             # 04의 lockfile 캐시 키
    paths: [ node_modules/ ]

test:
  stage: test
  needs: [build]                                    # DAG — build 후 즉시(stage 안 기다림)
  script: [ "pytest" ]
  parallel:
    matrix:
      - PY: ["3.11", "3.12", "3.13"]                # Actions matrix와 동일

deploy:
  stage: deploy
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'             # Actions if:와 동일
  environment: production                            # 06의 environment
  script: [ "kubectl apply -f ..." ]
```

Actions와의 큰 차이 하나: **stage가 1급 개념**입니다. GitLab은 "stage 순서 = 기본 실행 순서"이고, `needs:`로 그 순서를 건너뛰어 DAG(더 빠른 병렬)를 만듭니다. Actions는 stage가 없고 `needs:`만으로 순서를 표현합니다.

## 3. GitLab 러너 — Actions 러너와 비교

| | GitHub Actions | GitLab Runner |
|---|---|---|
| 호스팅 | GitHub-hosted / self-hosted | shared(GitLab.com) / self-managed |
| 실행 방식 | VM/컨테이너 | **executor** 선택: shell/docker/**kubernetes**/ssh |
| K8s 통합 | ARC(08) | **Kubernetes executor**(네이티브) |
| 격리 | 잡마다 새 환경 | executor에 따라(docker/k8s는 격리) |

GitLab의 **Kubernetes executor**가 08의 ARC에 대응합니다 — 잡마다 Pod를 만듭니다. 그리고 같은 함정이 그대로: 퍼블릭 프로젝트에 self-managed 러너 붙이지 말 것, ephemeral 유지, IMDS 차단(08). 도구가 달라도 위험은 이식됩니다.

## 4. 통합 철학 — GitLab이 한 제품에 넣은 것

```
Git 호스팅 + CI/CD + 컨테이너 레지스트리 + 환경/배포 추적
  + 리뷰앱(MR마다 임시 환경 자동 생성)
  + 내장 보안 스캔(SAST/DAST/의존성 — 21의 일부를 내장)
  + 이슈/보드/위키
= "하나의 DevOps 플랫폼"
```

특히 **리뷰앱**(Review Apps)이 강력합니다: MR(=PR)마다 그 브랜치를 배포한 임시 환경을 자동 생성 → 리뷰어가 실제 동작을 보고 리뷰. Actions로 하려면 여러 조각을 조립해야 하는 것을 GitLab은 내장합니다.

대가(guide의 저울질): 벤더 종속, 각 기능의 깊이(내장 SAST < 전문 도구), 그리고 셀프호스팅 시 운영 부담(GitLab 자체가 무거운 애플리케이션).

## 5. 언제 GitLab인가

| 상황 | 경향 |
|------|------|
| 이미 GitLab로 소스 관리 | CI도 GitLab(통합 이점) |
| 셀프호스팅/에어갭 환경 | GitLab(온프레 성숙) |
| 통합된 단일 플랫폼 선호 | GitLab |
| GitHub 생태계/마켓플레이스 | Actions |
| 멀티툴 조합(best-of-breed) | Actions + 전문 도구 |

"우월"이 아니라 맥락 — 09의 결정 프레임과 같습니다.

## 6. 소스/도구에서 확인하기

- GitLab CI/CD 문서: https://docs.gitlab.com/ee/ci/
- `.gitlab-ci.yml` 레퍼런스 / CI Lint 도구(파이프라인 검증)
- GitLab Runner: https://docs.gitlab.com/runner/ (Kubernetes executor)
- GitLab은 오픈소스(Community Edition) — 기여 가능(cicd 기여 트랙의 대안 목적지)

## 요약 카드

| 질문 | 답 |
|------|----|
| 핵심 교훈? | 개념 이식성 — 매핑표로 90% 번역 |
| Actions와 큰 차이? | **stage가 1급 개념** (기본 순서), needs로 DAG |
| K8s 러너? | Kubernetes executor (08 ARC 대응, 같은 함정) |
| 통합 철학? | 하나의 DevOps 플랫폼 (레지스트리·리뷰앱·스캔 내장) |
| 통합의 대가? | 벤더 종속 + 기능 깊이 + 셀프호스팅 부담 |
| 선택 기준? | 맥락(GitLab 소스·온프레·통합 선호 vs GitHub 생태계) |
