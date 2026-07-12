# 21 — 프로덕션 업그레이드: runbook을 실제로 굴리기

> k8s 35가 원리(skew·drain·PDB·비가역)를 가르쳤다면, 이 모듈은 **EKS 프로덕션에서의 실행**입니다 — insights API를 게이트로, 애드온을 정합으로, 그리고 노드 플릿을 다섯 가지 전략(관리형 롤링/Blue-Green NG/Karpenter drift/Fargate/Auto Mode) 중 하나로. 실무 트랙의 개막 모듈: "분기마다 반복 가능한 절차"를 실제 클러스터에서 완성합니다.

## 학습 목표

1. EKS 버전 수명주기(표준 14개월 + 연장 유료)를 **버전 정책 문서**로 만듭니다
2. cluster insights를 CLI 워크플로로 — preflight를 스크립트화합니다
3. 업그레이드 표면 4종(CP/애드온/노드/워크로드)의 순서와 게이트를 실행 명령 수준으로 압니다
4. 노드 플릿 전략 5종을 비교하고, **Blue/Green 노드그룹 전환을 직접 수행**합니다
5. 대규모(노드 수십~수백 대)의 시간 산수와 용량 여유(13) 계획을 세웁니다

## 선행: k8s 35(원리 — 필수), eks 05(노드그룹), 11(애드온), 17(Karpenter drift) · 환경: 공유 EKS
## ⚠️ lab-02는 실험용 노드그룹 2개(소형)를 생성 — 비용 소량, cleanup 필수

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-preflight-plan.md](./lab-01-preflight-plan.md) — 실클러스터 preflight + 계획서
3. [lab-02-bluegreen-nodes.md](./lab-02-bluegreen-nodes.md) — Blue/Green 노드그룹 전환 실연
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
