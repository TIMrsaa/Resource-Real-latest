# 이론 — Pipeline as Code, 아키텍처, 플러그인의 양날, 마이그레이션

> **🌱 17세 눈높이 비유: 오래된 만능 공구함 vs 신형 전동공구**
> - **Jenkins** = 40년 된 목수의 만능 공구함 — 서랍마다 특수 공구(플러그인)가 있어 **뭐든** 만듭니다. 단, 공구가 녹슬거나(플러그인 취약점) 서로 안 맞거나(버전 충돌), 그 공구함을 관리하는 것 자체가 일입니다
> - **GitHub Actions** = 신형 무선 전동공구 세트 — 깔끔하고 충전(관리)이 필요 없지만, 만능 공구함의 그 특수 공구가 없을 수 있습니다
> - **Controller/Agent** = 공구함(controller)은 하나뿐이고 여러 작업대(agent)에 공구를 빌려줍니다 — 공구함이 부서지면 전부 멈춥니다(SPOF)
> - **마이그레이션** = 40년치 공구를 신형 세트로 옮기기 — 어떤 특수 공구는 신형에 없어서, "그 공구로 뭘 했는지"부터 알아야 합니다

---

## 1. Pipeline as Code — Jenkinsfile

Jenkins도 이제 "UI 클릭"이 아니라 코드입니다(Jenkinsfile을 저장소에):

```groovy
// Declarative Pipeline (권장 — 구조적)
pipeline {
    agent { kubernetes { ... } }          // 어디서 실행 (Actions runs-on)

    environment {                          // env
        IMAGE = "myapp:${env.GIT_COMMIT.take(12)}"
    }

    stages {                               // Actions jobs (순차)
        stage('Test') {
            steps {                        // Actions steps
                sh 'pytest'
            }
        }
        stage('Build') {
            when { branch 'main' }         // Actions if:
            steps {
                sh "docker build -t ${IMAGE} ."
            }
        }
    }

    post {                                 // Actions if: always() / GitLab after_script
        always { junit 'test-results/*.xml' }    // 05의 테스트 리포트
        failure { slackSend '빌드 실패' }
    }
}
```

- **Declarative**(위): 구조가 강제됨, 읽기 쉬움 — 권장
- **Scripted**: 순수 Groovy, 무제한 유연 — 복잡, 유지보수 어려움

12의 매핑표가 여기서도 작동합니다: stage=job, steps=steps, when=if, post=always. **어휘만 Groovy입니다.**

## 2. 아키텍처 — Controller/Agent (상태성)

```
┌─ Jenkins Controller (상태 있음!) ─────────┐
│  - 잡 정의, 빌드 히스토리, 플러그인, 설정  │
│  - 웹 UI, 스케줄링                         │
│  - ★ 이게 죽으면 전부 멈춤 (SPOF)          │
│  - ★ 백업·HA·업그레이드가 우리 책임         │
└────────────┬───────────────────────────────┘
             │ 잡 분배
     ┌───────┴────────┐
  Agent 1          Agent 2      ← 실제 빌드 실행
```

GitHub Actions(03)의 **무상태** 모델과 근본적 대조:

| | Jenkins | GitHub Actions |
|---|---|---|
| 상태 | Controller가 보유(빌드 히스토리·설정) | 없음(GitHub이 관리) |
| SPOF | Controller | 없음 |
| 백업/HA | **우리 책임** | GitHub |
| 업그레이드 | **우리 책임**(플러그인 호환 지옥) | 자동 |
| 통제 | 완전(온프레·에어갭) | 제한적 |

이 상태성이 Jenkins의 힘(완전한 통제)이자 부채(운영 부담)입니다.

## 3. Jenkins on Kubernetes — 상태성을 완화

Kubernetes plugin으로 **agent를 Pod로**(08의 ARC, 12의 k8s executor와 같은 사상):

```groovy
agent {
    kubernetes {
        yaml '''
          spec:
            containers:
            - name: build
              image: golang:1.23
        '''
    }
}
// → 잡마다 Pod 생성, 끝나면 삭제 (ephemeral — 08의 격리)
```

이것으로 **agent의 상태성·확장 문제는 해결**됩니다(Karpenter로 확장, eks 17). 하지만 **controller는 여전히 상태를 갖습니다** — controller Pod는 PV에 설정·히스토리를 저장하고, 그 백업·업그레이드는 여전히 우리 몫입니다. "Jenkins를 K8s에 올렸다"가 상태성을 없애지는 않습니다.

## 4. 플러그인 생태계 — 양날

```
힘: 1,800+ 플러그인 — 어떤 도구/클라우드/프로토콜과도 연결
    (AWS, K8s, Slack, Jira, 특수 하드웨어, 레거시 시스템...)
    → "무엇이든 된다"가 Jenkins가 40년 산 이유
```

```
대가:
  ① 공급망 위험 (21): 플러그인은 서드파티 코드가 controller에서 실행됨
     → 취약 플러그인 하나가 controller(=모든 시크릿) 장악
  ② 유지보수 부채: 플러그인 간 버전 충돌, controller 업그레이드 시 호환성 지옥
  ③ 방치된 플러그인: 유지보수 중단된 플러그인에 의존 → 보안 패치 없음
```

플러그인 관리 규율: 필요한 것만 설치, 정기 업데이트, 유지보수 상태 확인, controller 백업 후 업그레이드. eks 11의 "관리형 애드온"이 주던 안전(AWS가 호환성 검증)을 Jenkins에서는 우리가 집니다.

## 5. Shared Library — 06의 대응

파이프라인 재사용:

```groovy
// vars/standardBuild.groovy (공유 라이브러리)
def call(Map config) {
    pipeline {
        agent { kubernetes { ... } }
        stages {
            stage('build') { steps { sh "docker build -t ${config.image} ." } }
        }
    }
}

// Jenkinsfile에서
@Library('my-shared-lib') _
standardBuild(image: 'myapp:latest')
```

06의 reusable workflow와 같은 목적(중복 제거)·같은 위험(중앙 라이브러리 = 폭발 반경). 공유 라이브러리 저장소도 프로덕션 코드로 보호해야 합니다(06 pitfall 5).

## 6. 마이그레이션 판단 — 떠날 것인가

```
떠나는 이유:
  - 운영 부담(controller HA·백업·플러그인 업그레이드)이 큼
  - 보안(플러그인 공급망, 방치된 controller)
  - 개발자 경험(UI 중심 레거시 잡, 코드화 안 됨)

머무는 이유:
  - 플러그인으로만 되는 특수 통합(레거시 시스템, 특수 하드웨어)
  - 에어갭/규제로 SaaS 불가
  - 40년치 잡의 이식 비용
```

마이그레이션 전략(eks 23·02의 사상 재사용):

```
❌ 빅뱅: 전부 한 번에 옮기기 → 실패(kubefed의 교훈, eks 23)
✅ 점진(strangler fig): 새 파이프라인은 새 도구로, 기존은 그대로
   → 잡을 하나씩 이전, 각 이전이 독립적으로 완료 가능(02의 브랜치 바이 앱스트랙션)
   → "무엇을 하는 잡인지" 문서화 먼저 (UI 잡은 대개 문서가 없습니다)
```

## 7. 소스/도구에서 확인하기

- Jenkins: https://www.jenkins.io / https://github.com/jenkinsci/jenkins (오픈소스, 기여 가능)
- Kubernetes plugin: https://plugins.jenkins.io/kubernetes/
- Jenkins Pipeline 문법: https://www.jenkins.io/doc/book/pipeline/syntax/
- JCasC(Configuration as Code): controller 설정도 코드로 — 상태성 완화의 핵심

## 요약 카드

| 질문 | 답 |
|------|----|
| Jenkins가 오래 산 이유? | 플러그인(무엇이든) + 온프레 완전 통제 + 벤더 독립 |
| Actions와 근본 차이? | Controller의 **상태성**(SPOF·백업·업그레이드가 우리 책임) |
| K8s에 올리면? | agent는 ephemeral 해결, controller는 여전히 상태 보유 |
| 플러그인의 대가? | 공급망 위험(21) + 유지보수 부채 + 방치 |
| Shared Library? | 06 reusable workflow 대응 (같은 폭발 반경 위험) |
| 마이그레이션 전략? | 빅뱅❌ → 점진(strangler fig), 잡 문서화 먼저 |
