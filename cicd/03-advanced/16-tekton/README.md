# 16 — Tekton: 쿠버네티스 네이티브 CI

> 14~15에서 CD가 K8s 네이티브(GitOps 컨트롤러)가 됐습니다. Tekton은 **CI도 K8s 네이티브**로 만듭니다 — 파이프라인이 YAML/CRD이고, 각 단계가 Pod로 실행되며, 재사용 단위(Task)가 클러스터 리소스입니다. GitHub Actions가 SaaS에 매인 것과 대조적으로, Tekton은 "어디서든 도는 CI를 클러스터가 소유한다". 이 모듈은 그 CRD 모델(Task/Pipeline/TaskRun)과 그것이 언제 정당한지를 다룹니다.

## 학습 목표

1. Tekton의 CRD 모델(Task/Pipeline/TaskRun/PipelineRun)을 앞의 CI 개념으로 매핑합니다
2. 각 Task가 Pod로, step이 컨테이너로 실행되는 구조를 이해합니다
3. Workspace(볼륨 공유)와 재사용(Tekton Hub의 Task)을 다룹니다
4. Tekton Triggers로 이벤트 기반 실행(webhook)을 구성합니다
5. "언제 Tekton인가" — SaaS CI 대비 정당성(멀티클라우드·온프레·플랫폼 구축)을 판단합니다

## 선행: 03(CI 개념), 12(이식성), 14(K8s 네이티브·CRD), k8s 30(Operator/CRD) · 환경: 공유 EKS
## ⚠️ 비용: Task가 Pod로 실행 → 노드 사용. cleanup 필수

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-task-pipeline.md](./lab-01-task-pipeline.md) — Task/Pipeline/Run, Pod 실행 관찰
3. [lab-02-triggers-and-choice.md](./lab-02-triggers-and-choice.md) — Triggers, 선택 기준
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
