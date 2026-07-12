# 11 — 배포 전략의 구현: Blue/Green과 카나리를 실제로

> 01에서 배포 전략 스펙트럼(재생성→롤링→블루/그린→카나리)을 개념으로 배웠고, "안전은 관찰 후 확대에서 온다"고 했습니다. 이 모듈은 그것을 **실제 트래픽 전환**으로 구현합니다 — CodeDeploy의 배포 구성(ECS/Lambda/EC2), 그리고 k8s에서의 대응물. eks 14(ALB 가중치)·20(메시 트래픽 분할)이 여기서 배포 자동화로 수렴합니다. 17(Progressive Delivery)의 기초 모듈.

## 학습 목표

1. 배포 전략을 "트래픽을 어떻게 옮기는가"의 관점에서 구현 수준으로 이해합니다
2. CodeDeploy의 배포 구성(all-at-once / canary / linear)과 대상(ECS/Lambda/EC2)을 압니다
3. 자동 롤백의 트리거(알람·헬스체크)와 그 전제(관찰 가능성)를 설계합니다
4. k8s에서의 대응물(Deployment 전략, 그리고 17의 Rollouts 예고)을 매핑합니다
5. DB 마이그레이션이 왜 이 모든 전략의 예외인지(expand-contract) 이해합니다

## 선행: 01(배포 전략), 09(CodePipeline), eks 14(ALB 트래픽)·20(메시) · 도구: AWS CLI
## ⚠️ 비용: ECS/ALB 실습 시 과금 — cleanup 필수. 개념 위주로 축소 가능

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-traffic-shifting.md](./lab-01-traffic-shifting.md) — 배포 구성과 트래픽 전환 관찰
3. [lab-02-rollback-and-db.md](./lab-02-rollback-and-db.md) — 자동 롤백, expand-contract 마이그레이션
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
