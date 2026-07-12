# 07 — VPC CNI 심층: IP의 경제학

> 중급 개막. k8s 27(CNI 일반론)에서 예고한 EKS 네트워킹의 본진 — ENI와 IP가 어떻게 할당되고, 왜 고갈되고, prefix delegation이 무엇을 바꾸는지. **EKS 운영 장애 빈도 1위(IP 고갈 — 16에서 실전)의 원리편.**

## 학습 목표

1. ENI/IP 할당 모델(인스턴스 타입별 한도, warm pool)을 수식 수준으로 압니다
2. ipamd의 동작(워밍업, 할당, 반환)을 로그/메트릭으로 관측합니다
3. prefix delegation이 maxPods를 어떻게 바꾸는지 계산하고 적용합니다
4. custom networking(Pod 전용 서브넷)과 SG-for-Pod의 용도를 압니다
5. "이 노드에 Pod 몇 개?"를 계산으로 답합니다

## 선행: k8s 27(CNI), eks 05(노드그룹) · 환경: 공유 EKS

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-eni-ip-anatomy.md](./lab-01-eni-ip-anatomy.md) — ENI/IP 실측, ipamd 관측
3. [lab-02-prefix-delegation.md](./lab-02-prefix-delegation.md) — prefix 모드 적용과 maxPods 재계산
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
