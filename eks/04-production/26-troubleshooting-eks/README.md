# 26 — EKS 장애 진단: 10대 시나리오와 계층 심문법

> k8s 38이 클러스터 안의 진단 루틴(describe → logs → events)을 가르쳤다면, EKS의 장애는 **경계를 넘습니다**: Pod가 안 뜨는 진짜 이유가 서브넷 IP 고갈(16)이고, 인증 실패의 원인이 IAM 신뢰 정책(09)이고, 502의 범인이 ALB deregistration(14)입니다. 이 모듈은 그 경계 위의 진단법 — 계층 심문 순서와 EKS 특유의 10대 장애를 증상→확진→처방으로 정리합니다. 실무 트랙 졸업 모듈.

## 학습 목표

1. EKS 장애의 4계층(AWS 인프라 / EKS 관리면 / k8s 오브젝트 / 앱)과 **경계 증상**을 구분합니다
2. 증상별 심문 순서를 갖춥니다 — "어느 계층에 물어야 하는가"를 첫 3분에 판정
3. EKS 10대 장애를 증상→확진 명령→처방으로 암기합니다 (진단 카드)
4. 장애 3종을 **직접 재현하고 진단**합니다 (IP 고갈, IRSA 실패, ALB 502)
5. 진단 도구상자를 완성합니다 — netshoot, debug node, insights, Flow Logs, 감사 로그

## 선행: k8s 38(진단 루틴 — 필수), eks 07·09·14·16·18(각 장애의 배경) · 환경: 공유 EKS
## 이 모듈은 앞 25개 모듈의 종합 시험 — 각 장애가 어느 모듈의 지식을 요구하는지 표시했습니다

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-reproduce-diagnose.md](./lab-01-reproduce-diagnose.md) — 장애 3종 재현·진단
3. [lab-02-runbook-toolbox.md](./lab-02-runbook-toolbox.md) — 진단 카드 완성, 도구상자, 온콜 리허설
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
