# 02. Service / 네트워킹 — ClusterIP, NodePort, LoadBalancer, Ingress, DNS

## 학습 목표

K8s에서 Pod 사이의 통신, 외부 노출, 이름 해석이 어떻게 일어나는지 손에 익힌다.

- **Service** 4가지 타입의 차이와 선택 기준
- **CoreDNS** 동작과 클러스터 내부 DNS
- **Ingress** 와 Ingress Controller의 역할 (개념만 — 실 ALB 연동은 Part 2)
- **kube-proxy** 가 뒤에서 하는 일

## 선행 지식

- 모듈 01 완료
- Pod, Deployment, Namespace 개념 익숙

## 진행 순서

1. [theory.md](./theory.md) — 이론 (20분)
2. [lab-01-clusterip.md](./lab-01-clusterip.md) — ClusterIP + Endpoint (20분)
3. [lab-02-nodeport-lb.md](./lab-02-nodeport-lb.md) — NodePort, LoadBalancer (30분)
4. [lab-03-dns.md](./lab-03-dns.md) — CoreDNS 직접 질의 (15분)
5. [quiz.md](./quiz.md)
6. [pitfalls.md](./pitfalls.md)
7. `bash cleanup.sh`

## 소요 시간

총 **약 1.5 ~ 2시간**.

## 예상 비용

LoadBalancer Service를 만들면 ALB/NLB가 생성되므로 **반드시 lab 끝나고 cleanup**.
- NLB: 시간당 약 0.0225 USD
- 1시간 학습 가정: 약 0.05 USD 추가

## 다음 모듈

→ [03-config-storage](../03-config-storage/)
