# 22 — Cilium 심층: eBPF가 커널을 다시 쓰는 법

> 04의 네트워킹 지도에서 "지각 변동"이라 부른 그것. Cilium은 CNI 하나가 아니라 **eBPF로 데이터 경로를 재건축한 프로젝트**입니다 — kube-proxy를 대체하고(iptables 체인 → 해시맵), 정책을 데이터 경로에서 집행하며(identity 기반), 관찰(Hubble)과 암호화와 부분적 메시까지 같은 자리에서 합니다. 이 모듈은 그 "같은 자리"의 정체를 팝니다: eBPF 프로그램이 어디에 붙는가, identity란 무엇인가, 그리고 이 통합이 무엇을 얻고 무엇을 잃는가.

## 학습 목표

1. eBPF의 실행 모델(훅 지점, 검증기, 맵)과 커널 프로그래밍의 안전성 보장을 이해합니다
2. Cilium의 데이터 경로(tc/XDP 훅, endpoint, service 맵)를 실제로 열어봅니다
3. **identity 기반 정책** — 왜 IP가 아니라 라벨 집합인가 — 을 이해하고 L3/L4/L7 정책을 실습합니다
4. kube-proxy 대체(eBPF Service 라우팅)와 그 성능·관찰 이점을 확인합니다
5. Hubble로 데이터 경로에서 직접 관찰하고, 트러블슈팅 도구(cilium-dbg)를 손에 넣습니다

## 선행: 04(네트워킹 지도 — 필수), 03(런타임·커널), eks 18(패킷 경로), 20(DNS) · 도구: kind, kubectl, helm, cilium CLI
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-ebpf-datapath.md](./lab-01-ebpf-datapath.md) — eBPF 프로그램·맵 열어보기, kube-proxy 대체
3. [lab-02-identity-policy-hubble.md](./lab-02-identity-policy-hubble.md) — identity, L3/L4/L7 정책, Hubble 관찰
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 3h
