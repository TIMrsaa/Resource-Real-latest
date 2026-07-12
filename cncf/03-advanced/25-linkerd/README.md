# 25 — Linkerd 심층: 단순함이라는 설계 철학

> 04의 메시 층에서 Istio(24)의 반대편. Linkerd는 같은 문제(mTLS·트래픽·관측)를 정반대의 철학으로 풉니다 — Envoy 대신 **자체 개발한 Rust 마이크로프록시**(linkerd2-proxy), 방대한 CRD 대신 최소한의 설정, "메시가 보이지 않아야 한다"는 원칙. 이 모듈은 그 설계 결정의 근거(왜 Envoy를 안 쓰나, 왜 기능을 덜 넣나)와 대가(무엇을 포기했나)를 팝니다. 24와 나란히 놓으면 48(선택 가이드)의 핵심 대비가 완성됩니다: **기능의 최대치(Istio) vs 운영의 최소치(Linkerd).**

## 학습 목표

1. Linkerd의 아키텍처(control plane + linkerd2-proxy)와 Istio와의 구조적 차이를 압니다
2. 왜 Envoy가 아니라 전용 Rust 프록시인가 — 그 설계 트레이드오프를 이해합니다
3. 자동 mTLS(설정 없이 켜짐)와 그 신원 모델을 확인합니다
4. 골든 메트릭(자동 생성)과 진단(linkerd viz, tap)을 실습합니다
5. "기능 최대(Istio) vs 운영 최소(Linkerd)"의 축으로 메시를 선택하는 법을 압니다

## 선행: 24(Istio — 대비), 23(Envoy), 04(지도), eks 20(메시) · 도구: kind, kubectl, linkerd CLI
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-simplicity-and-mtls.md](./lab-01-simplicity-and-mtls.md) — 설치·주입·자동 mTLS의 단순함
3. [lab-02-metrics-and-comparison.md](./lab-02-metrics-and-comparison.md) — 골든 메트릭, Istio와 직접 대비
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
