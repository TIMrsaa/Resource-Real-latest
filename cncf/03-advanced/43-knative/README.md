# 43 — Knative: 쿠버네티스 위의 서버리스

> 08의 5단에서 "Knative는 K8s 위에 서버리스 추상을 얹는다"고 스쳤습니다. 이 모듈이 그 실체입니다. **Knative Serving**은 요청이 없으면 Pod를 0으로 줄이고(scale-to-zero) 요청이 오면 순식간에 띄우며(0→N), 리비전·트래픽 분할로 카나리·블루그린을 기본 제공합니다. **Knative Eventing**은 40에서 배운 CloudEvents를 라우팅합니다(Broker·Trigger). Knative는 "함수(FaaS)가 아니라 컨테이너 기반 서버리스" — Lambda의 편의를 K8s 이식성 위에서 얻는 시도입니다. 이 모듈은 scale-to-zero의 메커니즘(Activator·오토스케일러 KPA), 리비전·트래픽 관리, Eventing의 CloudEvents 라우팅, 그리고 18(KEDA)·15(Knative Eventing 언급)와의 관계를 파고, "서버리스를 K8s로"의 트레이드오프를 따집니다.

## 학습 목표

1. Knative Serving의 scale-to-zero 메커니즘(Activator·KPA 오토스케일러)을 압니다
2. 리비전(Revision)·트래픽 분할로 카나리·블루그린을 하는 방식(08의 배포 전략)을 압니다
3. Knative Eventing의 CloudEvents(40) 라우팅(Broker·Trigger·Source)을 압니다
4. Knative와 18(KEDA)의 관계·차이(둘 다 이벤트 스케일이지만 다른 층)를 압니다
5. "서버리스를 K8s로"의 트레이드오프(콜드스타트·복잡성 vs 이식성·효율)를 판단합니다

## 선행: 08(오토스케일·배포 전략 — 필수), 40(CloudEvents), 18(KEDA 대비), 24(트래픽 관리) · 도구: kind, kubectl, Knative(kn/func 선택)
## 비용: 없음 (kind + Knative quickstart)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-serving-scale-to-zero.md](./lab-01-serving-scale-to-zero.md) — Serving, scale-to-zero, 리비전·트래픽
3. [lab-02-eventing-and-tradeoffs.md](./lab-02-eventing-and-tradeoffs.md) — Eventing(CloudEvents 라우팅), 트레이드오프
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
