# 05 — 관리형 노드그룹: 표준 모드의 노드 운영

> Auto Mode(04)가 가져간 일을 "직접 하는 쪽"의 정석. 노드그룹의 뒷면(ASG/시작 템플릿), AMI 선택(AL2023 vs Bottlerocket), 라벨/taint 설계, 롤링 업데이트 제어 — 기존 클러스터의 대부분이 아직 이 세계입니다.

## 학습 목표

1. 노드그룹의 3층 구조(EKS 객체 → ASG → EC2)를 해부합니다
2. AMI 계열(AL2023/Bottlerocket)의 차이와 선택 기준을 압니다
3. 용도별 노드그룹(라벨+taint 콤보)을 설계합니다 — k8s 12/34의 인프라판
4. 시작 템플릿으로 노드를 커스터마이즈합니다 (nodeadm)
5. 업데이트 설정(maxUnavailable)과 노드 자동 복구를 다룹니다

## 선행: 모듈 01~02, k8s 12(taint)/35(drain) · 환경: 공유 EKS (노드그룹 추가/삭제 — 비용 주의)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-nodegroup-anatomy.md](./lab-01-nodegroup-anatomy.md) — 해부와 용도별 풀 설계
3. [lab-02-ami-updates.md](./lab-02-ami-updates.md) — Bottlerocket, 업데이트 제어, 자동 복구
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2h
