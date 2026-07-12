# 15 — NetworkPolicy: Pod 방화벽

> 모듈 09에서 확인한 "네임스페이스는 네트워크를 격리하지 않는다"의 해답. 기본 거부에서 시작하는 마이크로 세그멘테이션.

## 학습 목표

1. NetworkPolicy가 "허용 목록" 모델임을 이해합니다 (선택되는 순간 기본 거부)
2. ingress/egress, podSelector/namespaceSelector/ipBlock 문법을 다룹니다
3. 기본 거부 → 필요한 통신만 여는 설계 패턴을 실습합니다
4. DNS egress를 빼먹으면 모든 것이 깨지는 함정을 체험합니다
5. 정책의 집행자는 CNI임을 압니다 (EKS에서는 VPC CNI의 정책 기능 활성화 필요)

## 선행: 모듈 05, 09 · 환경: 공유 EKS (lab에서 VPC CNI 정책 기능 활성화)
## 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-default-deny.md](./lab-01-default-deny.md) — 집행자 활성화, 기본 거부, 선별 허용
3. [lab-02-namespace-egress.md](./lab-02-namespace-egress.md) — ns 간 정책, egress와 DNS 함정
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 1.5h
