# 25 — 프로덕션 보안: 심층 방어를 AWS와 함께

> k8s 파트에서 보안의 부품들을 배웠습니다 — RBAC(11), PSA(32), NetworkPolicy(15), admission(23). 이 모듈은 그것들을 **EKS의 AWS 통합**과 엮어 심층 방어(defense in depth)로 세웁니다: 이미지→노드→런타임→네트워크→시크릿→감사의 6개 관문, GuardDuty의 런타임 위협 탐지, Secrets Manager CSI, 그리고 "침해를 가정한" 설계. 실무 트랙의 보안 종합.

## 학습 목표

1. EKS 심층 방어 6관문을 그리고, 각 관문의 k8s 부품과 AWS 서비스를 매핑합니다
2. Secrets Manager CSI Driver로 시크릿을 클러스터 밖에 두고 회전까지 잇습니다 — etcd 평문 문제의 해결
3. GuardDuty EKS Protection(감사 로그 + 런타임)의 탐지 범위를 이해합니다
4. 침해 시나리오를 admission·NetworkPolicy·IMDS 차단으로 다층 방어합니다 (실습)
5. 감사 로그(21)를 보안 관점으로 재독하고 대응 자동화의 뼈대를 세웁니다

## 선행: k8s 11(RBAC), 15(NetPol), 23(admission), 32(PSA), eks 09(IRSA/IMDS), 12(감사 로그), 18(네트워크) · 환경: 공유 EKS
## ⚠️ GuardDuty는 계정 전역 유료 — 이 모듈은 "이해+CLI 확인"으로, 활성화는 계정 관리자 협의

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-secrets-csi.md](./lab-01-secrets-csi.md) — Secrets Manager CSI, 회전, etcd 대조
3. [lab-02-defense-layers.md](./lab-02-defense-layers.md) — 침해 시나리오 다층 방어 실습
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2.5h
