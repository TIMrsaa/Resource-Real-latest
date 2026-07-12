# 27 — CNI 내부: Pod 네트워킹의 배선

> RunPodSandbox(모듈 26)에서 호출된 "CNI ADD"의 안쪽. CNI 스펙, 플러그인 체인, veth 페어와 라우팅을 노드에서 직접 추적하고, Pod→Pod 패킷의 전체 경로를 그립니다.

## 학습 목표

1. CNI 스펙(ADD/DEL, 설정 파일, 플러그인 체인)을 이해합니다
2. veth 페어 — Pod와 노드를 잇는 가상 랜선 — 를 직접 찾아냅니다
3. EKS VPC CNI의 동작(ENI/IP 할당, VPC 라우팅)을 노드에서 관측합니다
4. 오버레이(VXLAN) 방식과 VPC 네이티브 방식의 차이를 압니다
5. K8s 네트워크 4대 요구사항과 "왜 NAT 없이 Pod끼리 통신 가능한가"를 설명합니다

## 선행: 모듈 01(NET ns), 05, 26 · 환경: 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-veth-tracing.md](./lab-01-veth-tracing.md) — Pod의 랜선 찾기, 패킷 추적
3. [lab-02-vpc-cni.md](./lab-02-vpc-cni.md) — ENI/IP 관측, CNI 설정 파일 해부
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
