# 41 — 소스에서 빌드: 내가 컴파일한 Kubernetes 띄우기

> 기여자 트랙 개막. kubernetes/kubernetes를 클론해 **직접 빌드한 바이너리로 클러스터를 띄웁니다** — "쓰는 사람"과 "만드는 사람"의 경계를 넘는 첫 발. 여기부터는 전부 로컬(무료)입니다.

## 학습 목표

1. kubernetes/kubernetes 리포를 클론하고 빌드 환경을 갖춥니다 (Go, make)
2. 컴포넌트 하나(kubectl)를 빌드해 내 수정이 반영되는 것을 봅니다
3. kind로 "내가 빌드한 K8s 이미지"의 클러스터를 띄웁니다
4. 코드 수정 → 빌드 → 클러스터 반영의 **기여 루프**를 한 바퀴 돕니다

## 선행: 모듈 30/31(Go와 K8s 코드 감각), 21~28(각 컴포넌트의 동작) · 환경: 로컬 (WSL2, 메모리 8GB+, 디스크 40GB+)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-clone-build.md](./lab-01-clone-build.md) — 클론, kubectl 빌드, 첫 수정
3. [lab-02-kind-custom-build.md](./lab-02-kind-custom-build.md) — 내 빌드로 클러스터 기동
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2.5h (빌드 대기 포함)
