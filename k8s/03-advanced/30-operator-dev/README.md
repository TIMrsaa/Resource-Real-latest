# 30 — Operator 개발: kubebuilder로 컨트롤러 만들기

> 모듈 24의 CRD(명사)에 드디어 동사를 붙입니다. kubebuilder로 Website Operator를 직접 구현 — reconcile 루프, owner 설정, status 보고, finalizer까지. **이 커리큘럼에서 처음으로 Go 코드를 작성하는 모듈.**

## 학습 목표

1. kubebuilder 프로젝트 구조(API 타입, Reconciler, RBAC 마커)를 압니다
2. Reconcile 함수를 구현합니다: Website → Deployment+Service 생성/동기화
3. ownerReference(자동), status 갱신, requeue를 다룹니다
4. finalizer로 외부 자원 정리를 구현합니다
5. 로컬 실행(make run)으로 EKS 클러스터를 조정하는 개발 루프를 익힙니다

## 선행: 모듈 24(필수!), Go 기초 문법 · 환경: 로컬 Go 1.24+ + 공유 EKS
## 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-scaffold-api.md](./lab-01-scaffold-api.md) — 스캐폴드, API 타입 정의
3. [lab-02-reconcile.md](./lab-02-reconcile.md) — Reconcile 구현과 검증
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 3h (Go 경험에 따라 ±)
