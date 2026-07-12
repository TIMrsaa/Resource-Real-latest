# 01. 핵심 개념 — Pod, ReplicaSet, Deployment, Namespace

> **💡 일상 비유로 이해하기**
> 
> 핵심 객체들을 **카페 운영**에 비유해보세요. Pod 는 **바리스타 1명+그가 쓰는 머신 묶음**(작업 단위), ReplicaSet 은 **항상 바리스타 3명을 유지하라는 규칙**, Deployment 는 **신메뉴 레시피로 교대 교체하는 매니저**, Namespace 는 **본점/지점 구역 분리**입니다.

## 학습 목표

Kubernetes에서 가장 자주 마주칠 4개 객체의 **무엇을, 왜, 어떻게**를 손에 익힌다.

- **Pod**: 컨테이너의 K8s 단위 — 1개 이상의 컨테이너를 묶어 한 단위로 스케줄링
- **ReplicaSet**: Pod의 복제본 수 보장 (직접 쓸 일은 거의 없지만 동작 이해 필수)
- **Deployment**: ReplicaSet 위에 롤링 업데이트/롤백 기능을 얹은 추상화 — 실무 표준
- **Namespace**: 논리적 격리 (RBAC, 네트워크 폴리시의 기본 단위)

## 선행 지식

- Part 1 [README](../README.md) 의 EKS 클러스터 생성 완료
- `kubectl get nodes` 가 `Ready` 노드를 출력해야 함

## 진행 순서

1. [theory.md](./theory.md) — 이론 (15~20분)
2. [lab-01-pod.md](./lab-01-pod.md) — 첫 Pod 배포 (20분)
3. [lab-02-deployment.md](./lab-02-deployment.md) — Deployment + 롤링 업데이트 (30분)
4. [lab-03-namespace.md](./lab-03-namespace.md) — Namespace 격리 시연 (15분)
5. [quiz.md](./quiz.md) — 자가 점검
6. [pitfalls.md](./pitfalls.md) — 흔한 함정 5선
7. `bash cleanup.sh`

## 소요 시간

총 **약 2시간**.

## 예상 비용

EKS 클러스터가 이미 떠있다면 모듈 자체의 추가 비용은 거의 없음 (~0.3 USD).

## 매니페스트 위치

- `manifests/pod.yaml` — 단일 Pod
- `manifests/deployment.yaml` — Deployment + ReplicaSet
- `manifests/namespace.yaml` — Namespace 예시

## 다음 모듈

→ [02-services-networking](../02-services-networking/)
