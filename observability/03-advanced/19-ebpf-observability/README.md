# 19 — eBPF 관측: 계측 없는 관측의 약속과 한계

> 04부터 반복된 트레이스의 벽 — "앱이 계측되어야 신호가 태어난다"(그리고 그 조직적 마찰). eBPF 관측은 그 벽을 커널에서 우회하려는 시도입니다: 커널의 시스템 콜·네트워크 스택에 프로그램을 심어(cncf 22의 그 eBPF) **앱을 건드리지 않고** 통신·성능 신호를 뽑아냅니다. 이 모듈은 Cilium Hubble(네트워크 흐름 관측 — cncf 22의 연장), Pixie류 자동 관측(프로토콜 파싱으로 HTTP·DB 호출을 자동 가시화), 커널 수준 골든 시그널의 원리를 다루고 — 그리고 정직하게 **한계**를 다룹니다: eBPF는 "무엇이 오갔나"를 보지만 앱 내부의 "왜"와 분산 컨텍스트 전파(trace_id 릴레이)는 대체하지 못합니다. OTel 계측(11)과의 관계는 대체가 아니라 보완입니다.

## 학습 목표

1. eBPF 관측의 원리(커널 훅에서 신호 추출)와 "계측 제로"의 의미를 압니다
2. Hubble로 네트워크 흐름(L4/L7)을 관측합니다 (cncf 22의 관측 확장)
3. 프로토콜 파싱 기반 자동 관측(Pixie류)의 능력과 위치를 압니다
4. eBPF 관측의 한계(앱 내부·컨텍스트 전파·암호화 트래픽)를 정확히 압니다
5. OTel 계측과의 역할 분담(보완 관계)을 설계합니다

## 선행: cncf 22(eBPF·Cilium — 필수), 04(트레이스의 벽), 11(OTel) · 도구: kind, cilium CLI
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-hubble-flows.md](./lab-01-hubble-flows.md) — Cilium+Hubble로 계측 없는 흐름 관측
3. [lab-02-limits-and-complement.md](./lab-02-limits-and-complement.md) — 한계 확인·OTel과의 분담
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
