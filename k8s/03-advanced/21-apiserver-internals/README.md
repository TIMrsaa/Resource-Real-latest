# 21 — API 서버 내부: 요청의 일생

> 고급 트랙 개막. `kubectl apply` 한 번이 API 서버 안에서 거치는 전체 파이프라인을 해부하고, 각 단계를 직접 관측합니다. 이후 모든 고급 모듈(웹훅, CRD, 스케줄러...)이 이 지도 위에 섭니다.

## 학습 목표

1. 요청 파이프라인(인증→인가→admission→검증→etcd)을 단계별로 설명합니다
2. watch 메커니즘과 resourceVersion의 의미를 압니다
3. 낙관적 동시성 제어(conflict 에러)를 재현하고 이해합니다
4. API Priority & Fairness(APF)가 과부하에서 무엇을 보호하는지 압니다
5. 감사 로그(audit)로 "누가 무엇을 했나"를 추적합니다 (EKS 기준)

## 선행: 모듈 02, 10, 11 · 환경: 공유 EKS · 비용: CloudWatch 로그 소량

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-request-pipeline.md](./lab-01-request-pipeline.md) — -v=8 해부, conflict 재현, watch 관찰
3. [lab-02-audit-apf.md](./lab-02-audit-apf.md) — EKS 감사 로그, APF 흐름 관찰
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2h
