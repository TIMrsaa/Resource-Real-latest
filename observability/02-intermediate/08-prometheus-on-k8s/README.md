# 08 — Prometheus 온 K8s: 스크레이프를 운영합니다

> 03에서 메트릭의 원리를, cncf 11에서 Prometheus의 내부(TSDB·카디널리티)를 배웠습니다. 이 모듈은 그것을 **K8s 위에서 운영**합니다 — kube-prometheus-stack(Operator)으로 배포하고, **ServiceMonitor/PodMonitor**라는 선언형 스크레이프(누구를 긁을지를 CRD로), **relabeling**(수집 시점의 라벨 통제 — 카디널리티 수문), **recording rules**(비싼 쿼리를 미리 계산), 그리고 익스포터 3대장(node-exporter·kube-state-metrics·cAdvisor)의 역할 구분까지. "Prometheus를 깐다"가 아니라 "수집 대상이 늘고 바뀌는 클러스터에서 스크레이프 체계를 유지한다"가 주제입니다. 여기서 세운 체계 위에 09(대시보드)·10(알림)·14(AMP)가 올라갑니다.

## 학습 목표

1. kube-prometheus-stack(Operator 패턴)의 구성 요소와 역할을 압니다
2. ServiceMonitor/PodMonitor로 스크레이프 대상을 선언형으로 관리합니다
3. relabeling으로 라벨을 통제합니다 (drop·rename — 카디널리티 수문)
4. 익스포터 3대장(node-exporter·KSM·cAdvisor)이 각각 무엇의 메트릭인지 구분합니다
5. recording rules로 비싼 쿼리를 사전 계산하고, PromQL 실전 패턴을 익힙니다

## 선행: 03(메트릭 원리 — 필수), cncf 11(TSDB·카디널리티 — 병행 강력 권장) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-stack-and-servicemonitor.md](./lab-01-stack-and-servicemonitor.md) — 스택 배포, 앱을 ServiceMonitor로 등록
3. [lab-02-relabeling-and-rules.md](./lab-02-relabeling-and-rules.md) — relabeling 수문, recording rules
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2.5h
