# 12 — 스케줄링: Pod를 원하는 곳에, 원하는 분포로

> 스케줄러(모듈 02)에게 "희망사항"과 "금지사항"을 전달하는 모든 방법: nodeSelector, affinity, taint/toleration, topology spread, priority.

## 학습 목표

1. nodeSelector → nodeAffinity의 표현력 차이를 압니다
2. taint(노드가 밀어냄)와 toleration(견딤)의 방향성을 헷갈리지 않습니다
3. pod affinity/anti-affinity로 "같이/떨어져" 배치를 설계합니다
4. topologySpreadConstraints로 AZ 균등 분산을 구현합니다 (고가용성의 핵심)
5. PriorityClass와 선점(preemption)을 이해합니다

## 선행: 모듈 02, 04, 09 · 환경: 공유 EKS · 비용: 추가 없음 (노드 라벨만 활용)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-selector-affinity-taint.md](./lab-01-selector-affinity-taint.md)
3. [lab-02-spread-priority.md](./lab-02-spread-priority.md)
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
