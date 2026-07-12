# 03 — Pod 해부

> K8s의 최소 단위 Pod를 분해합니다: 왜 컨테이너가 아니라 Pod인가, pause 컨테이너의 정체, init/sidecar, 라이프사이클.

## 학습 목표

1. Pod = "namespace를 공유하는 컨테이너 그룹"임을 모듈 01 지식과 연결해 설명합니다
2. pause(infra) 컨테이너의 존재 이유를 압니다
3. initContainer와 네이티브 sidecar(1.36 기준 GA)를 구분해 사용합니다
4. Pod 라이프사이클(phase/condition)과 restartPolicy를 이해합니다
5. 멀티 컨테이너 패턴(사이드카/앰배서더/어댑터)을 구분합니다

## 선행 지식: 모듈 01(namespace), 02(아키텍처) · 환경: 공유 EKS 클러스터 · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-pod-anatomy.md](./lab-01-pod-anatomy.md) — 멀티 컨테이너 Pod 만들고 pause/공유 namespace 확인
3. [lab-02-init-sidecar-lifecycle.md](./lab-02-init-sidecar-lifecycle.md) — init/sidecar, 종료 시퀀스 관찰
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요 시간: 이론 1h + 실습 1.5h
