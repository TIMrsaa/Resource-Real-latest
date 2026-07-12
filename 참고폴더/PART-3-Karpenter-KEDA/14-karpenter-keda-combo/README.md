# 14. Karpenter + KEDA Combo — 본 커리큘럼의 절정

## 학습 목표

지금까지 배운 모든 것을 한 시나리오로:

1. **SQS 에 메시지 1만 건 주입**
2. KEDA 가 payment-service Pod 0 → 30 으로 빠르게 스케일
3. Karpenter 가 노드 부족 감지 → Spot 노드 N대 자동 추가
4. 메시지 처리되는 동안 Pod / Node 그래프 시각화
5. 처리 완료 → KEDA 가 Pod 0 으로 → Karpenter 가 노드 회수
6. **인프라 비용은 처리량에 비례** 확인

## 선행 지식

- 모듈 10~13 완료
- payment-service 가 SQS IRSA 셋업되어 있음

## 진행 순서

1. [theory.md](./theory.md) — 시나리오 설계 (10분)
2. [lab-01-setup.md](./lab-01-setup.md) — 사전 셋업 + 베이스라인 (15분)
3. [lab-02-burst.md](./lab-02-burst.md) — 1만 건 주입 + 관찰 (40분)
4. [lab-03-analysis.md](./lab-03-analysis.md) — 결과 분석 + 비용 계산 (20분)
5. [quiz.md](./quiz.md)
6. [pitfalls.md](./pitfalls.md)
7. `bash cleanup.sh`

## 비용 주의

이 모듈은 노드를 일시적으로 5~10대까지 띄움. 1.5시간 가정 약 1 USD.

## 다음 모듈

→ [15-terraform-iac](../15-terraform-iac/)
