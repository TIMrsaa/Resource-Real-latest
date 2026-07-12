# 06. VPC CNI + Networking

## 학습 목표

- AWS VPC CNI 의 동작 원리 (Pod이 VPC 서브넷의 IP를 직접 사용)
- IP 한계와 prefix delegation 옵션
- AWS Load Balancer Controller 설치 (Helm + IRSA)
- ALB Ingress 만들어 외부 노출

## 선행 지식

- 모듈 05 완료 (`eks-study` 클러스터 떠 있음, OIDC 활성화)

## 진행 순서

1. [theory.md](./theory.md) — VPC CNI / LB Controller (20분)
2. [lab-01-cni-observation.md](./lab-01-cni-observation.md) — Pod IP 가 VPC 서브넷에서 옴 (20분)
3. [lab-02-alb-controller.md](./lab-02-alb-controller.md) — AWS LB Controller 설치 (30분)
4. [lab-03-alb-ingress.md](./lab-03-alb-ingress.md) — ALB Ingress 시연 (25분)
5. [quiz.md](./quiz.md)
6. [pitfalls.md](./pitfalls.md)

## 비용

ALB 1개 시간당 약 $0.0225 + LCU. 1.5시간 학습 가정 약 0.05 USD. 학습 끝나면 Ingress 삭제로 ALB 제거.

## 다음 모듈

→ [07-storage-irsa](../07-storage-irsa/)
