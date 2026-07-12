# 06 — Ingress와 Gateway API: L7 라우팅

> LB 하나로 여러 HTTP 서비스를 호스트/경로 기준으로 라우팅합니다. 구세대 표준(Ingress)과 현세대 표준(Gateway API)을 모두 다루되 Gateway API를 우선합니다.

## 학습 목표

1. L4(Service)와 L7(Ingress/Gateway) 라우팅의 차이를 설명합니다
2. Ingress 리소스와 "Ingress Controller가 따로 필요하다"는 구조를 이해합니다
3. Gateway API의 역할 분리 모델(GatewayClass/Gateway/HTTPRoute)을 이해하고 실습합니다
4. 왜 Gateway API가 Ingress를 대체하는지(표현력/역할분리/이식성) 압니다

## 선행 지식: 모듈 05 (Service) · 환경: 공유 EKS
## 비용: NGINX Gateway Fabric이 만드는 NLB ~$0.0225/h — 실습 후 삭제

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-ingress.md](./lab-01-ingress.md) — Ingress 한 바퀴 (레거시 이해용)
3. [lab-02-gateway-api.md](./lab-02-gateway-api.md) — Gateway API로 호스트/경로/가중치 라우팅
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요 시간: 이론 1h + 실습 2h
