# 08 — AWS Load Balancer Controller: Ingress의 실물

> k8s 06에서 Ingress/Gateway를 "규칙"으로 배웠다면, 여기선 그 규칙이 **ALB/NLB라는 AWS 실물**로 구현되는 전 과정 — 컨트롤러 설치부터 타겟 등록 방식(instance vs ip), LB 통합(비용!)까지. 14(트래픽 엔지니어링)의 토대.

## 학습 목표

1. AWS LB Controller의 동작(Ingress/Service → ALB/NLB 생성)을 이해하고 설치합니다
2. 타겟 타입 instance vs **ip**의 경로 차이를 패킷 레벨로 압니다 (k8s 28 연결)
3. ALB Ingress를 만들고 대상그룹/리스너/규칙의 실물을 AWS에서 확인합니다
4. `group.name`으로 Ingress 여러 개를 ALB 하나에 통합합니다 (비용 레버)
5. TargetGroupBinding으로 기존 LB에 Pod를 직접 연결합니다

## 선행: k8s 06(Ingress), eks 07(VPC CNI — ip 타겟의 전제), 09 미리보기(컨트롤러 권한) · 환경: 공유 EKS (⚠️ ALB 시간당 과금)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-install-alb-ingress.md](./lab-01-install-alb-ingress.md) — 설치, 첫 ALB, 실물 해부
3. [lab-02-nlb-group-tgb.md](./lab-02-nlb-group-tgb.md) — NLB, ALB 통합, TargetGroupBinding
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh` (★ LB 잔존 = 과금)

소요: 이론 1.5h + 실습 2h
