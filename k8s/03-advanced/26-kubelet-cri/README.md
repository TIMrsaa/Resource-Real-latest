# 26 — kubelet과 CRI: 노드에서 Pod가 태어나는 곳

> control plane을 떠나 노드로 내려갑니다. kubelet의 SyncLoop, CRI 규약, crictl로 containerd를 직접 조작하며 "Pod 생성의 마지막 1마일"을 해부합니다.

## 학습 목표

1. kubelet SyncLoop와 Pod 생성 타임라인(sandbox→init→containers)을 압니다
2. CRI gRPC 규약(RuntimeService/ImageService)을 이해하고 crictl로 직접 호출합니다
3. static Pod의 정체와 용도를 압니다
4. kubelet의 자원 관리(eviction, QoS 클래스)와 PLEG를 이해합니다
5. 노드 디버깅 루틴(kubelet 로그, crictl)을 익힙니다

## 선행: 모듈 01, 02, 03 · 환경: 공유 EKS (노드 debug 사용) · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-crictl.md](./lab-01-crictl.md) — crictl로 CRI 직접 체험
3. [lab-02-qos-eviction-static.md](./lab-02-qos-eviction-static.md) — QoS/eviction/static Pod
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
