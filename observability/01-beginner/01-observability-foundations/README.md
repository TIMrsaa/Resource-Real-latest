# 01 — 관측 가능성의 기초: 질문할 수 있는 시스템

> Part 5의 출발점. "모니터링은 이미 하고 있는데 왜 관측 가능성인가요?"에 답합니다. 모니터링은 **미리 정한 질문**(CPU가 80% 넘나요?)에 답하고, 관측 가능성은 **아직 하지 않은 질문**(왜 어제 오후 3시에 결제만 느렸지?)에 답할 수 있는 시스템의 성질입니다. 이 모듈은 신호 4종(메트릭·이벤트·로그·트레이스 — MELT)의 성격과 상호 보완을 정리하고, **K8s 클러스터에서 신호가 태어나는 곳 전부**(컨테이너 stdout, kubelet, cAdvisor, API 서버, Events, audit, 노드)를 지도로 그립니다. 이 지도가 Part 5 전체의 밑그림입니다 — 이후 모든 모듈은 이 지도 위의 경로(신호가 어디서 나와 어디로 흐르나)를 구축하는 이야기입니다.

## 학습 목표

1. 모니터링과 관측 가능성의 차이("미리 정한 질문" vs "새 질문")를 설명할 수 있습니다
2. 신호 4종(MELT)의 성격·강점·비용을 비교할 수 있습니다
3. K8s에서 각 신호가 태어나는 곳을 전부 나열할 수 있습니다 (신호의 원산지 지도)
4. "어떤 질문에 어떤 신호를 쓰나"의 감을 잡습니다 (05에서 완성)
5. 관측이 공짜가 아님(볼륨·카디널리티·보존 = 비용)을 처음부터 인지합니다 (22의 씨앗)

## 선행: k8s 파트 초급(Pod·노드·kubelet 이해), cncf 06(관측 지도 — 병행 가능) · 도구: kind, kubectl
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-signals-origin-tour.md](./lab-01-signals-origin-tour.md) — 신호의 원산지 투어 (stdout·metrics·events를 직접 확인)
3. [lab-02-monitoring-vs-observability.md](./lab-02-monitoring-vs-observability.md) — 같은 장애를 두 방식으로 조사해 차이 체감
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 1.5h
