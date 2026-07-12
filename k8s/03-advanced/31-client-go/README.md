# 31 — client-go 심층: informer를 직접 만들어봅니다

> kubebuilder(모듈 30)가 숨겨준 바닥 — clientset, informer, workqueue — 를 직접 조립합니다. 이걸 알면 controller-runtime이 "마법"이 아니라 "포장"임을 알게 되고, kubernetes/kubernetes 코드(기여자 트랙)가 읽히기 시작합니다.

## 학습 목표

1. 클라이언트 4종(clientset/dynamic/discovery/RESTClient)의 용도를 구분합니다
2. List+Watch → informer 캐시 → 이벤트 핸들러 → workqueue 파이프라인을 직접 짭니다
3. resync, RetryOnConflict, rate limiter 등 운영 디테일을 압니다
4. "K8s API를 쓰는 모든 도구"의 공통 뼈대를 이해합니다

## 선행: 모듈 21(watch/rv), 30 · 환경: 로컬 Go + 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-clients.md](./lab-01-clients.md) — 클라이언트 4종 사용
3. [lab-02-informer-workqueue.md](./lab-02-informer-workqueue.md) — 미니 컨트롤러를 맨손으로
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md)

소요: 이론 1.5h + 실습 2.5h
