# 05 — Service: 변하는 Pod들 앞의 고정 접점

> Pod IP는 소모품입니다. 그 앞에 "변하지 않는 주소"를 세우는 4가지 방법과 그 내부(EndpointSlice, kube-proxy)를 배웁니다.

## 학습 목표

1. Service 4종(ClusterIP/NodePort/LoadBalancer/ExternalName)의 용도와 포함 관계를 압니다
2. Service → EndpointSlice → Pod 연결 사슬을 추적할 수 있습니다
3. "Service에 연결이 안 돼요"를 selector/port/probe 순서로 디버깅합니다
4. EKS에서 LoadBalancer가 실제 NLB가 되는 과정을 봅니다
5. ClusterIP가 "가짜 IP"(iptables 규칙)임을 확인합니다

## 선행 지식: 모듈 04 (Deployment, label) · 환경: 공유 EKS
## 비용: lab-02의 NLB 약 $0.0225/h — 실습 후 즉시 삭제

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-clusterip-endpoints.md](./lab-01-clusterip-endpoints.md) — ClusterIP, 연결 사슬, 디버깅 훈련
3. [lab-02-nodeport-loadbalancer.md](./lab-02-nodeport-loadbalancer.md) — 외부 노출 2종 + NLB
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요 시간: 이론 1h + 실습 1.5h
