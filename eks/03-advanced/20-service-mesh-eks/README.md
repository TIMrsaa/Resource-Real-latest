# 20 — 서비스 메시: App Mesh 이후의 동서(東西) 트래픽 제어

> 14의 ALB는 남북(유저→클러스터) 트래픽의 손잡이였습니다. 서비스 수십 개가 **서로를** 부르기 시작하면 동서 트래픽에도 같은 요구가 생깁니다 — mTLS, 재시도, 서킷브레이커, 카나리아, 골든 메트릭. 그걸 앱 코드 수정 없이 얹는 것이 메시다. AWS의 답이었던 App Mesh는 종료됐습니다(2026-09 EOL) — 그 사건의 교훈과 함께, 현재의 표준 Istio로 원리를 익힙니다. 고급 트랙 졸업 모듈.

## 학습 목표

1. 메시가 푸는 문제(동서 트래픽의 L7 제어)와 **필요 신호/불필요 신호**를 구분합니다
2. App Mesh 종료가 남긴 교훈(관리형 락인의 양날)과 이후 선택지 지도를 그립니다
3. Istio의 구조(istiod + Envoy sidecar, 주입 웹훅)와 ambient의 차이를 압니다
4. mTLS를 STRICT로 올리고 — 메시 밖 침입자가 거부되는 것을 실측합니다
5. VirtualService/DestinationRule로 카나리아 분할·fault 주입·서킷브레이커를 실험합니다

## 선행: eks 14(ALB — 남북), 18(패킷 경로), k8s 15(NetPol — L3/4와의 분업), 23(웹훅) · 환경: 공유 EKS
## ⚠️ 리소스: sidecar가 Pod마다 메모리 수십 MB — 실험 ns에 한정, cleanup에서 완전 제거

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-istio-mtls.md](./lab-01-istio-mtls.md) — 설치, 주입, STRICT mTLS 실증
3. [lab-02-traffic-control.md](./lab-02-traffic-control.md) — 카나리아, fault 주입, 서킷브레이커
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2.5h
