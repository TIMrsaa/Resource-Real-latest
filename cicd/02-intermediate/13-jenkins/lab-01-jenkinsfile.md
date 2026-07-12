# Lab 01 — Jenkinsfile을 앞의 지식으로 읽기

로컬 Jenkins를 띄우고 Jenkinsfile을 작성하며, 12의 "개념 이식성"이 가장 다른 도구에서도 성립함을 확인합니다.

## Step 1. 로컬 Jenkins (Docker)

```bash
mkdir -p ~/ci-lab/jenkins && cd ~/ci-lab/jenkins
docker run -d --name jenkins-lab \
  -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  jenkins/jenkins:lts-jdk17

echo "초기 관리자 비밀번호:"
sleep 30
docker exec jenkins-lab cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "(아직 시작 중 — 잠시 후 재시도)"
echo "→ http://localhost:8080 에서 초기 설정 (Install suggested plugins)"
```

> Jenkins는 controller가 상태를 갖습니다(theory §2) — `jenkins_home` 볼륨이 그 상태입니다. 이 볼륨을 잃으면 모든 잡·설정·히스토리가 사라집니다(백업이 우리 책임).

## Step 2. Jenkinsfile 작성 — 12의 매핑표로 읽기

```bash
cat > Jenkinsfile <<'EOF'
pipeline {
    agent any                              // ← runs-on: (Actions) / executor (GitLab)

    environment {                          // ← env:
        APP = 'demo'
    }

    stages {                               // ← jobs: (순차 실행)
        stage('Lint') {                    // ← job
            steps {                        // ← steps:
                sh 'echo "[Lint] ruff check (Actions: run: ruff check)"'
            }
        }
        stage('Test') {
            steps {
                sh 'echo "[Test] pytest"'
                sh 'mkdir -p test-results && echo "<testsuite/>" > test-results/junit.xml'
            }
        }
        stage('Build') {
            when { branch 'main' }         // ← if: github.ref == 'refs/heads/main'
            steps {
                sh 'echo "[Build] docker build (main only)"'
            }
        }
    }

    post {                                 // ← if: always() (Actions) / after_script (GitLab)
        always {
            junit 'test-results/*.xml'     // ← 05의 테스트 리포트
            echo '항상 실행 (정리·리포트)'
        }
        failure {
            echo '실패 시 알림 (Slack 등)'
        }
    }
}
EOF
```

## Step 3. 대조표 — 세 도구 나란히 (산출물)

```markdown
# 같은 파이프라인, 세 어휘 (12의 이식성 최종 확인)
| 개념 | Jenkins | GitHub Actions | GitLab CI |
|------|---------|---------------|-----------|
| 실행 위치 | agent | runs-on | executor/tags |
| 순차 단위 | stage | job(+needs) | stage |
| 명령 | steps { sh } | steps: run: | script: |
| 조건 | when { branch } | if: | rules: |
| 환경변수 | environment {} | env: | variables: |
| 항상 실행 | post { always } | if: always() | after_script |
| 테스트 리포트 | junit | 별도 액션 | artifacts:reports |
| 재사용 | Shared Library | reusable workflow | include/extends |
→ 결론: 어휘만 다릅니다. 개념(12)은 완전히 이식됩니다.
```

## Step 4. 파이프라인 잡 생성·실행

```bash
# 저장소로 (Jenkins가 SCM에서 Jenkinsfile을 읽는 방식 — Pipeline as Code)
git init -q && git config user.email l@e.com && git config user.name L
echo "print('demo')" > app.py
git add -A && git commit -qm "init"

echo "Jenkins UI에서:"
echo "  1. New Item → Pipeline"
echo "  2. Pipeline → 'Pipeline script from SCM' (또는 직접 붙여넣기)"
echo "  3. Build Now → 콘솔 출력에서 stage 진행 확인"
echo "  → Stage View에서 Lint→Test→Build 시각화 (Actions의 잡 그래프 대응)"
```

## Step 5. Declarative vs Scripted — 왜 Declarative인가

```bash
cat > Jenkinsfile.scripted <<'EOF'
// Scripted Pipeline — 순수 Groovy (무제한 유연, 위험)
node {
    stage('Test') {
        try {
            sh 'pytest'
        } catch (e) {
            // 임의 로직 가능 — 그래서 유지보수 지옥이 되기 쉽습니다
            echo "복구 시도..."
            sh 'pytest --lf'
        }
    }
    // for 루프, 조건, 함수... 무엇이든 — 그리고 아무도 못 읽는 파이프라인이 됩니다
}
EOF
echo "Scripted는 강력하나, 팀 파이프라인은 Declarative로:"
echo "  - 구조가 강제되어 읽기 쉽다"
echo "  - Blue Ocean UI·검증 도구가 잘 동작"
echo "  - 복잡 로직이 필요하면 Shared Library로 격리(lab-02)"
```

## Step 6. 이식성의 증명 (산출물)

```markdown
# 이 파트에서 만난 CI 도구들 (이식성 최종 정리)
| 도구 | 1급 개념 | 철학 | 상태성 |
|------|---------|------|-------|
| GitHub Actions | 이벤트→워크플로 | 코드 중심, 마켓플레이스 | 무상태 |
| AWS Code 시리즈 | 파이프라인이 지휘 | AWS 깊은 통합 | 파이프라인이 리소스 |
| GitLab CI | stage | 통합 플랫폼 | 무상태(SaaS) |
| Jenkins | stage/plugin | 무엇이든·완전 통제 | **controller 상태** |

# 핵심 통찰
- 개념(빌드→테스트→배포, 러너, 아티팩트, 시크릿)은 100% 이식
- 차이는: 1급 개념, 철학, 상태성, 그리고 생태계
- 새 도구는 이 네 축으로 하루면 파악 (12의 교훈 확정)
```

## 정리

lab-02에서 K8s 배포와 마이그레이션을 다룹니다. Jenkins 컨테이너 유지.
