# 학습 가이드 — 긁는 자의 운영학

## Prometheus 운영의 실제 질문

cncf 11에서 pull 모델과 TSDB를 배웠습니다. K8s에서 운영하면 질문이 달라집니다:

```
"새 서비스가 배포됐습니다 — Prometheus가 어떻게 알고 긁지?"
"팀들이 각자 메트릭을 노출하는데, 수집 등록을 누가 관리하지?"
"어떤 익스포터가 어떤 메트릭을 주지? (노드? 오브젝트 상태? 컨테이너?)"
"라벨 폭발(03의 사고)을 수집 시점에 막을 수 없나요?"
"대시보드마다 무거운 쿼리를 반복 계산하는데 비용이…"
```

이 질문들의 답이 이 모듈의 네 기둥: **Operator(자동화)·ServiceMonitor(선언형 등록)·relabeling(수문)·recording rules(사전 계산)**입니다.

## Operator 패턴 — cncf 08의 재회

kube-prometheus-stack은 Prometheus Operator 기반입니다:

```
수동 운영: prometheus.yml에 scrape_configs를 손으로 → 변경마다 재로드
Operator: CRD로 선언 → Operator가 설정 생성·적용
  Prometheus CRD: 서버 스펙 (replicas·보존·리소스)
  ServiceMonitor/PodMonitor CRD: ★ 누구를 긁을지
  PrometheusRule CRD: recording/alerting rules
→ cncf 08(오퍼레이터=운영 지식의 코드화)이 관측 스택에 적용된 모습
```

핵심 효과: **수집 등록의 셀프서비스** — 앱 팀이 자기 네임스페이스에 ServiceMonitor를 배포하면(라벨 셀렉터로 매칭) Prometheus가 자동으로 긁기 시작합니다. 중앙 설정 파일 병목이 사라집니다(cncf 47의 셀프서비스 정신).

## 익스포터 3대장 — "그 메트릭 어디서 오나"

혼동 1순위. 세 소스의 역할을 명확히:

```
node-exporter (DaemonSet): 노드 OS의 메트릭
  CPU·메모리·디스크·네트워크 — "기계가 어떤가"
kube-state-metrics (KSM, Deployment): K8s 오브젝트 상태의 메트릭
  Deployment replicas·Pod phase·PVC 상태 — "선언과 상태가 어떤가"
  (API 서버의 오브젝트를 메트릭으로 번역 — 리소스 사용량 아님!)
cAdvisor (kubelet 내장, 01·03): 컨테이너의 리소스 사용
  container_cpu/memory — "컨테이너가 얼마나 쓰나"

예: "Pod가 Pending인 게 몇 개?" → KSM (kube_pod_status_phase)
    "그 Pod의 CPU 사용은?" → cAdvisor
    "그 노드 디스크 남았나요?" → node-exporter
```

이 구분이 대시보드(09)·알림(10) 작성의 어휘가 됩니다.

## relabeling — 03의 규율을 시스템으로

03에서 "unbounded 라벨 금지"를 배웠습니다. 하지만 남의 앱·서드파티 익스포터가 나쁜 라벨을 노출한다면? **수집 시점에 통제**합니다:

```
relabeling의 두 시점:
  relabelings(스크레이프 전): 대상 선택·타깃 라벨 조작
  metricRelabelings(스크레이프 후): ★ 메트릭·라벨 drop/rename
    — 나쁜 라벨 제거, 필요 없는 메트릭 폐기 (TSDB에 들어가기 전!)

→ 카디널리티의 수문이자 (06의 grep 필터의 메트릭판)
  22(비용)의 핵심 수단
```

## recording rules — 미리 계산해 두는 지혜

```
문제: histogram_quantile(0.99, sum by (le,service) (rate(...[5m])))
  → 대시보드 열 때마다, 알림 평가마다 이 무거운 걸 반복

recording rule: 주기적으로 계산해 새 시계열로 저장
  record: service:http_p99:5m
  expr: histogram_quantile(...)
→ 대시보드·알림은 저장된 결과를 조회 (빠르고 일관됨)
→ 21(SLO)의 번레이트 계산이 전부 이 위에
```

## 이 모듈이 놓는 다리

- ServiceMonitor 체계 → 09·10의 데이터 공급원
- metricRelabelings → 22(비용 통제)의 1차 수단
- recording rules → 21(SLO·번레이트)의 기반
- 이 스택 전체 → 14(AMP)에서 "수집은 그대로, 저장만 관리형으로"의 비교 대상
