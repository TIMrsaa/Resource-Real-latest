# 04 — 지도: 네트워킹 — 패킷이 지나는 모든 층에 프로젝트가 있습니다

> eks 18에서 패킷의 경로(검문소 3층)를 따라갔습니다 — 이 지도는 그 경로의 각 층을 담당하는 생태계 전체를 훑습니다: Pod 네트워크를 만드는 CNI들(Cilium·Calico·Flannel·vpc-cni), 이름을 IP로 바꾸는 CoreDNS, L7의 지배자 Envoy와 그 위에 지어진 것들(인그레스·게이트웨이·메시), 그리고 이 동네의 지각 변동인 eBPF(커널을 다시 프로그래밍합니다)까지. 네트워킹은 CNCF에서 Graduated가 가장 밀집한 카테고리입니다 — 층을 나누면 지도가 선명해집니다.

## 학습 목표

1. 네트워킹 스택을 4층(CNI / DNS·디스커버리 / 프록시·게이트웨이 / 메시)으로 나누고 각 층의 전수 지도를 그립니다
2. CNI 선택의 실질(오버레이 vs 라우팅, NetworkPolicy 지원, eBPF)과 vpc-cni(eks 16)의 위치를 압니다
3. eBPF가 왜 지각 변동인지 — iptables 체인과의 구조 차이 — 를 이해합니다
4. kind에서 Cilium을 CNI로 설치해 NetworkPolicy와 Hubble(플로우 관찰)을 시식합니다
5. Envoy가 "L7의 공용 부품"이 된 이유와 그 위의 건축물들(Contour·Emissary·Istio·Gateway API)을 연결합니다

## 선행: 01(범례), k8s 중급(Service·NetworkPolicy·Ingress), eks 16·18(vpc-cni·패킷 경로), eks 20(메시) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md) — 지도 본체
2. [lab-01-category-census.md](./lab-01-category-census.md) — 전수 목록·층 분류
3. [lab-02-cilium-taste.md](./lab-02-cilium-taste.md) — Cilium CNI + NetworkPolicy + Hubble 시식
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2h
