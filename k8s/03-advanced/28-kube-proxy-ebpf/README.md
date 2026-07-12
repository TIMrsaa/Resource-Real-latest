# 28 — kube-proxy 내부: iptables, IPVS, nftables, 그리고 eBPF

> 모듈 05의 "Service는 규칙이다"를 패킷 레벨로 완성합니다. 노드의 iptables 체인을 직접 읽고, conntrack을 관찰하고, eBPF 세대가 무엇을 바꾸는지 봅니다.

## 학습 목표

1. iptables 모드의 체인 구조(KUBE-SERVICES→KUBE-SVC→KUBE-SEP)를 직접 읽습니다
2. 확률 기반 분배(statistic 모듈)의 실체를 확인합니다
3. conntrack이 응답 경로를 처리하는 원리를 압니다
4. iptables vs IPVS vs nftables 모드의 차이와 규모 한계를 압니다
5. eBPF(Cilium)가 kube-proxy를 대체하는 구조를 개념적으로 이해합니다

## 선행: 모듈 05, 27 · 환경: 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-iptables-reading.md](./lab-01-iptables-reading.md) — 체인 추적 풀코스
3. [lab-02-conntrack-modes.md](./lab-02-conntrack-modes.md) — conntrack, 모드 비교 관찰
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
