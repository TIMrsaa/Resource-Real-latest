# 18 — Kustomize: 템플릿 없는 환경 분리

> kubectl에 내장된(-k) 또 하나의 표준. base/overlay 패치 모델, Helm과의 비교와 조합까지.

## 학습 목표

1. base/overlay 구조와 패치(strategic/JSON6902) 모델을 다룹니다
2. 제너레이터(configMapGenerator의 해시 접미사!)의 가치를 압니다
3. Helm vs Kustomize의 선택 기준과 조합 패턴(helm template | kustomize)을 압니다
4. kubectl -k 워크플로를 익힙니다

## 선행: 모듈 17 (비교 대상으로서) · 환경: 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-base-overlay.md](./lab-01-base-overlay.md) — dev/prod 오버레이 구축
3. [lab-02-generators-helm.md](./lab-02-generators-helm.md) — 해시 제너레이터, Helm 조합
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 45m + 실습 1.5h
