# 02 — K8s 아키텍처: 클러스터의 큰 그림

> 컨테이너(모듈 01)를 이해했으니, 이제 "그 컨테이너 수천 개를 누가 어떻게 지휘하는가"를 봅니다.
> 이 모듈의 그림 하나가 이후 43개 모듈 전부의 지도가 됩니다.

## 학습 목표

1. control plane 4대 컴포넌트(API서버/etcd/스케줄러/컨트롤러매니저)와 노드 컴포넌트(kubelet/kube-proxy/런타임)의 역할을 설명합니다
2. "선언적 API + 조정 루프"가 왜 K8s 설계의 전부인지 이해합니다
3. EKS 클러스터를 생성하고 각 컴포넌트의 실체를 직접 확인합니다
4. `kubectl run` 한 줄이 일으키는 전체 이벤트 체인을 추적합니다

## 선행 지식

- 모듈 01 (컨테이너 = 프로세스)
- AWS CLI 설정 완료

## 비용

EKS control plane $0.10/h + t3.medium Spot 2대 ≈ $0.13/h. **이 클러스터는 이후 모듈에서 계속 재사용합니다.**

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-create-cluster.md](./lab-01-create-cluster.md) — EKS 클러스터 생성 + 컴포넌트 실체 확인
3. [lab-02-trace-a-pod.md](./lab-02-trace-a-pod.md) — Pod 생성 한 번의 전체 여정 추적
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md)

소요 시간: 이론 1.5h + 실습 2h (클러스터 생성 대기 20분 포함)
