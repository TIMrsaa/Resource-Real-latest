# 15 — RPS로 스케일하기: Custom Metrics HPA와 KEDA

> k8s 26의 HPA는 CPU를 봤습니다 — 그런데 13에서 우리는 서비스의 진짜 한계가 "Pod당 몇 rps"임을 측정했습니다. 이 모듈은 그 측정값을 오토스케일링의 목표로 직결합니다: **"Pod당 무릎의 70%를 넘으면 늘려라"** — CPU라는 대리 지표를 버리고 원인 지표로.

## 학습 목표

1. CPU 기반 스케일링의 두 한계(후행성·간접성)와 RPS 기반의 우위를 설명합니다
2. 메트릭 API 3형제(metrics.k8s.io / custom / external)와 어댑터의 자리를 그립니다
3. Prometheus + Adapter로 custom.metrics API를 세우고 RPS HPA를 만듭니다
4. KEDA(ScaledObject)로 같은 목표를 달성하고, 두 경로의 선택 기준을 압니다
5. 13의 무릎 측정값으로 HPA target을 **산정**합니다 (감이 아니라 계산)

## 선행: k8s 26(HPA 공식·behavior), eks 12(메트릭 감각), 13(무릎 — target의 근거) · 환경: 공유 EKS
## ⚠️ 비용: Prometheus/KEDA는 클러스터 안(무과금), 부하 실험은 짧게

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-prometheus-adapter.md](./lab-01-prometheus-adapter.md) — custom.metrics API 개통, RPS HPA
3. [lab-02-keda.md](./lab-02-keda.md) — ScaledObject, 스케일 검증, 두 경로 비교
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
