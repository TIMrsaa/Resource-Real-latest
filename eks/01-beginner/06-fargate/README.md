# 06 — Fargate: 노드라는 개념의 소멸

> 초급 트랙 졸업 모듈. 노드그룹(05)·Auto Mode(04)와 또 다른 제3의 길 — **Pod 하나당 마이크로 VM 하나**. "노드 없음"의 대가로 받아들이는 제약 목록이 곧 이 모듈의 본문입니다.

## 학습 목표

1. Fargate의 실행 모델(1 Pod = 1 격리 VM)과 스케줄링 경로를 이해합니다
2. Fargate 프로파일(ns/라벨 셀렉터)로 워크로드를 Fargate에 보냅니다
3. 제약 목록(DaemonSet/EBS/hostPath/GPU 불가 등)을 직접 부딪혀 확인합니다
4. 요금 모델(Pod 단위 vCPU·메모리·초)과 사이징 반올림을 계산합니다
5. 노드그룹 vs Fargate vs Auto Mode 3자 결정표를 완성합니다 (초급 졸업 산출물)

## 선행: 모듈 04, 05 (비교 대상) · 환경: 공유 EKS

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-fargate-profile.md](./lab-01-fargate-profile.md) — 프로파일, 배포, 가상 노드 관찰
3. [lab-02-limits-decision.md](./lab-02-limits-decision.md) — 제약 부딪히기 + 3자 결정표
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 1.5h
