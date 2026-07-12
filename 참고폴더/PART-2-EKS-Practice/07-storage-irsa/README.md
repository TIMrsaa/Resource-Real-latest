# 07. Storage & IRSA

## 학습 목표

- **IRSA** (IAM Roles for Service Accounts) 메커니즘을 직접 구현
- **Pod Identity** (2024+ 신규 방식) 와 비교
- **EBS CSI Driver** 가 IRSA로 EBS API 호출하는 실제 흐름 확인
- 다른 워크로드 (S3 접근하는 앱) 에 IRSA 적용 실습

## 선행 지식

- 모듈 05~06 완료
- 클러스터 OIDC provider 활성화됨 (`iam.withOIDC: true`)

## 진행 순서

1. [theory.md](./theory.md) — IRSA 동작 원리 (20분)
2. [lab-01-ebs-csi-irsa.md](./lab-01-ebs-csi-irsa.md) — EBS CSI 의 IRSA 검증 (20분)
3. [lab-02-app-irsa-s3.md](./lab-02-app-irsa-s3.md) — 앱에 IRSA 적용 (S3 접근) (35분)
4. [lab-03-pod-identity.md](./lab-03-pod-identity.md) — Pod Identity 비교 (20분)
5. [quiz.md](./quiz.md)
6. [pitfalls.md](./pitfalls.md)

## 비용

- S3 GET/PUT 몇 번: < $0.001
- EBS gp3: ~$0.005/시간
- 무시 가능

## 다음 모듈

→ [08-observability](../08-observability/)
