# 03 — 메트릭의 원리: 숫자 4형, 노출 형식, 그리고 두 개의 메트릭 세계

> 01에서 메트릭이 이미 도처에 있음을 봤습니다(cAdvisor·API 서버). 이 모듈은 메트릭이라는 신호 자체를 팝니다 — **4가지 타입**(counter·gauge·histogram·summary)이 왜 나뉘고 각각 어떤 질문에 맞는지, Prometheus **노출 형식**(이름·라벨·값·HELP/TYPE)의 문법, 그리고 K8s에 공존하는 **두 메트릭 세계** — 리소스 메트릭 파이프라인(metrics-server → kubectl top·HPA)과 모니터링 파이프라인(Prometheus → 대시보드·알림) — 의 구분. "kubectl top과 Grafana 숫자가 왜 다르죠?"라는 실무 단골 질문이 이 구분에서 풀립니다. counter가 왜 값이 아니라 rate()로 읽어야 하는지, histogram이 왜 p99의 근사인지 — 08(Prometheus 운영)과 21(SLO)의 기초가 여기입니다.

## 학습 목표

1. 메트릭 4형(counter/gauge/histogram/summary)의 성격과 용도를 구분합니다
2. Prometheus 노출 형식을 읽고 쓸 수 있습니다 (앱 메트릭 노출 실습)
3. counter는 rate()로, histogram은 분위수 근사로 읽는 이유를 압니다
4. 리소스 메트릭 파이프라인(metrics-server)과 모니터링 파이프라인(Prometheus)의 역할 분리를 압니다
5. 라벨 설계의 기초(무엇을 라벨로, 무엇을 절대 라벨로 하면 안 되나 — 카디널리티)를 압니다

## 선행: 01(원산지 — 필수), cncf 11(Prometheus 내부 — 병행 권장) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-metric-types-and-format.md](./lab-01-metric-types-and-format.md) — 4형 노출·읽기, counter와 rate의 감각
3. [lab-02-two-metric-pipelines.md](./lab-02-two-metric-pipelines.md) — metrics-server 설치, kubectl top vs 모니터링 메트릭
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 1.5h
