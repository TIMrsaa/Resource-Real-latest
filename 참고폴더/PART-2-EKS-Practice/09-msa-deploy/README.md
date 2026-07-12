# 09. 시나리오 MSA 앱 EKS 배포

## 학습 목표

지금까지 배운 모든 개념을 통합 — `scenarios/` 의 5개 Go 마이크로서비스를 EKS 에 배포.

- ECR 이미지 사용
- 각 서비스에 적합한 K8s 객체 매핑 (Deployment / StatefulSet 없음 — DB 외부 의존성 없는 디자인)
- ALB Ingress 로 외부 노출 (frontend, order-service)
- gRPC 내부 통신 (order → user)
- SQS / Kafka 외부 큐 (payment, notification) — Part 3 에서 KEDA 와 연동

## 선행 지식

- 모듈 05~08 완료
- ECR 에 시나리오 앱 5종 푸시 완료 (`bash 00-prerequisites/scripts/ecr-push-all.sh`)
- AWS LB Controller 동작 확인

## 진행 순서

1. [theory.md](./theory.md) — MSA 배포 아키텍처 (15분)
2. [lab-01-prepare.md](./lab-01-prepare.md) — Namespace, SA, 외부 의존성 (20분)
3. [lab-02-deploy-services.md](./lab-02-deploy-services.md) — 5개 서비스 배포 (40분)
4. [lab-03-end-to-end.md](./lab-03-end-to-end.md) — E2E 트래픽 + 모니터링 (25분)
5. [quiz.md](./quiz.md)
6. [pitfalls.md](./pitfalls.md)
7. `bash cleanup.sh`

## 비용

ALB 1개 (시간당 $0.0225) + EBS 볼륨 + 노드. 학습 1.5시간 가정 약 0.2 USD.

## Part 2 종료

이 모듈을 마치면 Part 2 종료. **클러스터를 삭제하거나 Part 3 까지 유지**.

```bash
# Part 2 끝나고 잠시 쉬려면 클러스터 삭제 (비용 정지):
eksctl delete cluster --name eks-study --region ap-northeast-2

# 또는 Part 3 바로 시작하려면 클러스터 유지
```
