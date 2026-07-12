# 29 — Dapr 심층: 앱 코드 위의 추상

> 08의 사다리 5단에서 "앱 코드 위의 추상"으로 분류한 그것. Dapr(Distributed Application Runtime)은 다른 메시·게이트웨이와 근본적으로 다른 곳을 겨냥합니다 — 네트워크가 아니라 **애플리케이션의 분산 시스템 관심사**(상태 관리, pub/sub, 시크릿, 서비스 호출, 재시도)를 사이드카 API로 추출합니다. "마이크로서비스가 반복 구현하는 것들을 런타임으로 밀어낸다"가 Dapr의 아이디어입니다. 이 모듈은 그 빌딩블록 모델, 컴포넌트 추상(같은 코드로 Redis든 DynamoDB든), 그리고 메시(24·25)와 무엇이 다른지를 팝니다.

## 학습 목표

1. Dapr의 사이드카 모델과 빌딩블록(state/pubsub/secrets/invocation/bindings)을 압니다
2. 컴포넌트 추상 — 앱 코드는 그대로, 백엔드를 설정으로 교체 — 을 이해합니다
3. Dapr와 서비스 메시(24·25)의 차이 — 앱 관심사 vs 네트워크 관심사 — 를 압니다
4. 상태 관리·pub/sub를 실습하고, 컴포넌트 교체의 이식성을 확인합니다
5. "Dapr가 맞는가"(다언어·분산 관심사 표준화) 판단과 그 대가(또 하나의 API·의존)를 압니다

## 선행: 08(사다리 5단), 24·25(메시 — 대비), 09(데이터·pub/sub), 12(OTel) · 도구: kind, kubectl, dapr CLI
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-building-blocks.md](./lab-01-building-blocks.md) — 사이드카, state·pub/sub, 컴포넌트 추상
3. [lab-02-portability-and-mesh.md](./lab-02-portability-and-mesh.md) — 백엔드 교체, 메시와의 차이·공존
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
