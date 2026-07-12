# 이론 — CRD 모델, Pod 실행, Workspace, Triggers, 선택

> **🌱 17세 눈높이 비유: 레고 블록 CI**
> - **GitHub Actions** = 완성된 장난감(SaaS) — 사서 바로 놉니다
> - **Tekton** = 레고 블록 세트 — **Task(블록)** 를 조립해 **Pipeline(작품)** 을 만듭니다. 자유롭지만 조립은 내 몫
> - **step = 블록 안의 색깔 층** = 각 컨테이너
> - **PipelineRun = 실제로 조립을 실행한 결과물**
> - **Workspace = 블록들이 공유하는 받침판** — 여러 Task가 같은 볼륨에 결과물을 놓습니다
> - **Triggers = 자동 조립 로봇** — git push가 오면 자동으로 조립 시작
> - 대부분의 사람은 완성 장난감(Actions)이 낫습니다. 레고(Tekton)는 **자기만의 장난감 공장(플랫폼)을 지을 때** 씁니다

---

## 1. CRD 모델 — CI가 쿠버네티스 리소스

```
Task         재사용 가능한 단위 (steps = 컨테이너들)
Pipeline     Task들의 조합 (순서·의존)
TaskRun      Task의 실행 인스턴스 (→ Pod)
PipelineRun  Pipeline의 실행 인스턴스 (→ 여러 Pod)
```

매핑(12의 이식성):

| Tekton | GitHub Actions | Jenkins | 비고 |
|--------|---------------|---------|------|
| Task | composite action | Shared Library 함수 | 재사용 단위 |
| step | step | steps.sh | 컨테이너/명령 |
| Pipeline | workflow | pipeline | 조합 |
| PipelineRun | workflow run | build | 실행 |
| Workspace | artifacts(볼륨) | archive | 공유 저장 |
| params | inputs | parameters | 입력 |

**결정적 차이**: Task/Pipeline이 **클러스터 리소스**(kubectl로 조회·관리)입니다. Actions 워크플로가 저장소 파일인 것과 달리, Tekton 파이프라인은 etcd에 삽니다.

## 2. Pod 실행 모델 — step이 컨테이너

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata: { name: build }
spec:
  steps:
    - name: compile              # ← 컨테이너 1
      image: golang:1.23
      script: "go build -o app ."
    - name: test                 # ← 컨테이너 2 (같은 Pod, 순차)
      image: golang:1.23
      script: "go test ./..."
```

- 하나의 **TaskRun = 하나의 Pod**, 각 **step = 그 Pod의 컨테이너**(순차 실행)
- step들은 같은 Pod라 **볼륨을 공유**(03의 "같은 잡의 스텝은 파일 공유"와 동형)
- 리소스 요청·노드 선택·보안 컨텍스트가 전부 K8s 그대로 — Pod니까(k8s 파트 전체가 적용!)

이 모델의 힘: CI 실행 환경이 **완전히 쿠버네티스**입니다. Karpenter로 확장(eks 17), NetworkPolicy로 격리(eks 18), PSA로 보안(eks 32) — CI에 클러스터의 모든 도구가 적용됩니다.

## 3. Workspace — Task 간 데이터 공유

```yaml
# Pipeline에서 Task 간 소스·아티팩트 전달
spec:
  workspaces:
    - name: shared               # PVC나 emptyDir
  tasks:
    - name: fetch
      taskRef: { name: git-clone }
      workspaces: [{ name: output, workspace: shared }]
    - name: build
      taskRef: { name: build }
      runAfter: [fetch]           # 의존 (Actions needs)
      workspaces: [{ name: source, workspace: shared }]   # fetch가 받은 소스를 build가 씀
```

Workspace는 03의 잡 간 전달(artifacts)에 대응하되 **볼륨 기반**입니다 — Task들이 같은 PVC를 마운트해 소스·빌드 산출물을 넘깁니다. PVC냐 emptyDir이냐로 지속성/성능을 조절.

## 4. Triggers — 이벤트 기반 실행

Tekton 코어는 "실행"만 압니다(kubectl로 PipelineRun 생성). 자동 트리거는 **Tekton Triggers**가 담당:

```
EventListener (webhook 수신 Pod)
  → TriggerBinding (webhook 페이로드에서 값 추출: git url, sha)
  → TriggerTemplate (PipelineRun을 생성)
```

git push → webhook → EventListener → PipelineRun 생성. GitHub Actions의 `on: push`가 내장인 것과 달리, Tekton은 이것을 **명시적으로 조립**합니다 — 로우레벨의 대가이자 유연성.

## 5. 재사용 — Tekton Hub

Task가 클러스터 리소스라 공유가 자연스럽습니다:

```bash
# Tekton Hub의 검증된 Task 설치 (06의 재사용과 동형)
tkn hub install task git-clone
tkn hub install task kaniko        # 데몬 없이 이미지 빌드 (04·19)
```

Tekton Hub는 재사용 가능한 Task 카탈로그(git-clone, kaniko, buildah, s2i…). 06의 reusable workflow, 13의 Shared Library와 같은 목적 — 그리고 같은 위험(공급망: 설치하는 Task는 클러스터에서 실행되는 코드, 21).

## 6. 언제 Tekton인가 — 판단

| 상황 | Tekton | SaaS CI(Actions 등) |
|------|--------|--------------------|
| 클러스터가 이미 중심 | ✔ (통합) | |
| 멀티클라우드·온프레·에어갭 이식성 | ✔ | (SaaS 종속) |
| CI 플랫폼을 직접 구축(플랫폼 팀) | ✔ (엔진) | |
| 빠른 시작·개발자 경험 | | ✔ (완성품) |
| UI·마켓플레이스·생태계 | | ✔ |
| 팀이 작음·표준 워크플로 | | ✔ |

정직한 결론: **대부분의 조직은 SaaS CI가 맞습니다.** Tekton은 로우레벨이라 그 위에 플랫폼을 얹는 조직(OpenShift Pipelines, Jenkins X, 사내 IDP)이나 특수 이식성 요구에 정당합니다. "K8s 네이티브니까 무조건 좋다"는 함정 — 조립 비용을 지불할 이유가 있어야 합니다.

## 7. 소스/도구에서 확인하기

- Tekton: https://github.com/tektoncd/pipeline (CNCF Graduated — 28의 tekton 기여 대상)
- Tekton Hub: https://hub.tekton.dev
- Triggers: https://github.com/tektoncd/triggers
- tkn CLI: https://github.com/tektoncd/cli

## 요약 카드

| 질문 | 답 |
|------|----|
| Tekton의 정체? | CI가 K8s CRD/Pod로 — 클러스터가 CI 엔진 |
| CRD 모델? | Task/Pipeline(정의) + TaskRun/PipelineRun(실행) |
| 실행 단위? | TaskRun=Pod, step=컨테이너 (k8s 전부 적용) |
| Task 간 데이터? | Workspace(볼륨 공유) |
| 트리거? | Tekton Triggers(EventListener) — 명시적 조립 |
| 재사용? | Tekton Hub(Task 카탈로그) — 공급망 주의(21) |
| 언제? | 이식성·플랫폼 구축 — 대부분은 SaaS가 맞음 |
