# 18 — KEDA 심층: 이벤트가 스케일을 정합니다

> 10의 지도에서 "KEDA vs Karpenter는 다른 층"이라는 것을 배웠습니다. 이 모듈은 그 워크로드 층을 팝니다 — KEDA는 HPA를 **대체하지 않고 확장**합니다: 외부 이벤트(큐 길이, Kafka lag, PromQL, cron, S3 객체 수...)를 HPA가 이해하는 external metrics API로 번역하고, HPA가 못 하는 scale-to-zero는 자기가 직접 처리합니다. 이 구조를 이해하면 "KEDA를 깔았는데 Pod가 안 뜬다"의 진단이 층으로 나뉘고, ScaledJob과 ScaledObject의 선택이 분명해지며, 콜드스타트라는 대가를 어디까지 받아들일지 판단할 수 있습니다.

## 학습 목표

1. KEDA의 3컴포넌트(operator/metrics-adapter/admission)와 HPA와의 관계를 정확히 압니다
2. scale-to-zero의 메커니즘(activation vs scaling)과 콜드스타트의 대가를 압니다
3. ScaledObject와 ScaledJob의 차이(장기 실행 vs 잡 단위)와 선택 기준을 압니다
4. 스케일러(트리거)의 인증(TriggerAuthentication)과 폴링 부하를 설계합니다
5. Karpenter(eks 17)와의 직렬 관계를 실험으로 확인하고 진단 층을 세웁니다

## 선행: 10(지도), k8s(HPA), eks 17(Karpenter), 11(PromQL) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-hpa-relationship.md](./lab-01-hpa-relationship.md) — KEDA가 만든 HPA, activation, scale-to-zero
3. [lab-02-scalers-and-jobs.md](./lab-02-scalers-and-jobs.md) — 큐 스케일러, ScaledJob, 진단 층
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
