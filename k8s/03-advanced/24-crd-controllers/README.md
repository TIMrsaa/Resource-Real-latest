# 24 — CRD와 컨트롤러 패턴

> K8s의 확장 모델 본체: 새 리소스 종류를 등록(CRD)하고, 그것을 조정 루프로 관리(컨트롤러)합니다. finalizer, ownerReference, server-side apply — 지금까지 흩어져 등장한 퍼즐들이 여기서 맞춰집니다.

## 학습 목표

1. CRD를 직접 설계합니다 (스키마, 검증, 버전, 서브리소스, 출력 컬럼)
2. ownerReference와 가비지 컬렉션(cascade 삭제)의 원리를 검증합니다
3. finalizer가 "Terminating에 갇히는" 메커니즘과 올바른 사용을 압니다
4. server-side apply의 필드 소유권 모델을 실습합니다
5. "CRD + 컨트롤러 = Operator"의 구도를 그립니다 (구현은 모듈 30)

## 선행: 모듈 21, 23 · 환경: 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-crd-design.md](./lab-01-crd-design.md) — CRD 설계 풀코스
3. [lab-02-owners-finalizers-ssa.md](./lab-02-owners-finalizers-ssa.md) — GC, finalizer, SSA
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
