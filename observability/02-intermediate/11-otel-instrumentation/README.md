# 11 — OTel 계측과 Collector: 트레이스가 실제로 흐르게

> 04에서 트레이스의 원리(span·전파)를 손으로 익혔습니다. 이 모듈은 그것을 **실제 시스템**으로 만듭니다 — OpenTelemetry SDK의 자동/수동 계측(코드를 얼마나 고쳐야 하나), K8s에서의 마법인 **OTel Operator의 자동 주입**(어노테이션 하나로 Java/Python 앱에 계측 심기), 그리고 **Collector의 배포 3패턴**(sidecar/DaemonSet(agent)/gateway)과 파이프라인 설정(receiver→processor→exporter — Fluent Bit과 같은 사상, 신호는 3종). cncf 12(OTel의 스펙·내부)가 이론이었다면 여기는 배치와 운영입니다. 이 Collector가 16(ADOT)에서 AWS판으로, 12모듈(Loki·Tempo)에서 백엔드 연결로 이어집니다.

## 학습 목표

1. 자동 계측 vs 수동 계측의 범위·비용을 구분하고 조합 전략을 세웁니다
2. OTel Operator의 Instrumentation CRD로 코드 수정 없는 계측 주입을 구현합니다
3. Collector 파이프라인(receiver·processor·exporter)을 신호 3종에 대해 설정합니다
4. 배포 3패턴(sidecar/agent/gateway)의 트레이드오프와 조합을 판단합니다
5. 샘플링(head 기본, tail의 위치)을 Collector에서 설정합니다 (04·cncf 12의 실전화)

## 선행: 04(trace 원리 — 필수), cncf 12(OTel 스펙 — 병행 강력 권장), 06(파이프라인 사상) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-auto-instrumentation.md](./lab-01-auto-instrumentation.md) — Operator 자동 주입으로 계측 없는 앱에 트레이스
3. [lab-02-collector-pipelines.md](./lab-02-collector-pipelines.md) — Collector 3패턴·파이프라인·샘플링
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2.5h
