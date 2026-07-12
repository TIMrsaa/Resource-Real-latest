# 18. Upgrade Strategy

## 학습 목표

- EKS 버전 정책 + 업그레이드 순서
- Control Plane → Addon → 노드 그룹 → 워크로드 호환성
- Blue/Green 클러스터 업그레이드 패턴
- Karpenter 노드의 자동 회전을 활용한 무중단 업그레이드

## 선행 지식

- Part 1~3 완료
- 클러스터 떠 있음

## 진행 순서

1. [theory.md](./theory.md) — 업그레이드 전략 (15분)
2. [lab-01-prereq-check.md](./lab-01-prereq-check.md) — 호환성 사전 점검 (15분)
3. [lab-02-control-plane.md](./lab-02-control-plane.md) — Control Plane 업그레이드 (20분)
4. [lab-03-nodes.md](./lab-03-nodes.md) — 노드 그룹 업그레이드 (25분)
5. [quiz.md](./quiz.md)
6. [pitfalls.md](./pitfalls.md)

## 비용

업그레이드는 약 30분 ~ 1시간. EC2 + Control Plane 비용만, 약 0.5 USD.

## 커리큘럼 종료

이 모듈을 마치면 18개 모듈 전부 완료입니다 🎉.
