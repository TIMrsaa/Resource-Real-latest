# 05. EKS 클러스터 (eksctl + ClusterConfig)

## 학습 목표

- EKS 클러스터의 구성 요소와 책임 분담을 이해
- eksctl + ClusterConfig YAML 로 재현 가능한 클러스터 만들기
- 관리형 노드 그룹 (Managed Node Group) vs Self-managed 차이
- addon 관리 (vpc-cni, coredns, kube-proxy, ebs-csi)
- OIDC provider 활성화 (IRSA의 전제 조건)

## 선행 지식

- Part 1 완료
- AWS CLI / eksctl 설치됨

## 진행 순서

1. [theory.md](./theory.md) — EKS 아키텍처 (15분)
2. [lab-01-create-cluster.md](./lab-01-create-cluster.md) — ClusterConfig로 클러스터 생성 (30분)
3. [lab-02-nodegroups.md](./lab-02-nodegroups.md) — 노드 그룹 추가/삭제, 스케일링 (20분)
4. [lab-03-addons.md](./lab-03-addons.md) — addon 관리 (20분)
5. [quiz.md](./quiz.md)
6. [pitfalls.md](./pitfalls.md)
7. (cleanup은 Part 2 끝에서 일괄)

## 소요 시간

총 **약 2 시간** (클러스터 생성에 15~20분).

## 비용

이 모듈에서 클러스터를 **만든 채로 둡니다** (이후 모듈에서 계속 사용).
시간당 약 0.13 USD (Control Plane + 노드 2대 spot).

## 다음 모듈

→ [06-vpc-cni-networking](../06-vpc-cni-networking/)
