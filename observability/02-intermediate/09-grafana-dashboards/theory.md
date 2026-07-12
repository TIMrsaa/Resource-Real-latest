# 이론 — RED/USE, 변수, 드릴다운, as code, 안티패턴

> **🌱 17세 눈높이 비유: 병원 상황판의 설계**
> - **그래프 벽(실패)** = 복도에 모니터 40개 — 의사가 응급 때 어딜 봐야 할지 모름
> - **RED(환자 상태판)** = 접수 수(Rate)·악화율(Errors)·대기시간(Duration) — "환자가 아픈가"
> - **USE(설비 상태판)** = 병상 가동률(Utilization)·대기 줄(Saturation)·고장(Errors) — "병원이 눌리는가"
> - **드릴다운(층별 안내)** = 종합 상황판 → 진료과 상황판 → 병상별 차트 — 클릭으로 내려감
> - **변수(과 선택 드롭다운)** = 진료과마다 상황판을 새로 만들지 않고, 하나의 판에서 과를 선택
> - **as code(설계 도면 보관)** = 상황판 구성을 도면(JSON)으로 — 실수로 지워도 재시공, 지점(환경)마다 동일 시공

---

## 1. RED — 서비스(요청 처리자)의 세 지표

```
Rate:     sum(rate(http_requests_total{...}[5m]))
Errors:   비율로! sum(rate(...{code=~"5.."}[5m])) / sum(rate(...[5m]))
Duration: histogram_quantile(0.5|0.95|0.99, sum by (le)(rate(..._bucket[5m])))
          → p50·p95·p99를 함께 (평균 금지 — 03)

패널 구성 관례 (서비스 대시보드 상단 3~4개):
  ① 요청율 (스택: code별)  ② 에러율 (임계선 표시)
  ③ 지연 분위수 (p50/p95/p99 세 선)  ④ (선택) 포화 — 재시도·큐

08의 recording rules(service:*)를 그대로 소비
  → 대시보드가 가볍고, 알림(10)과 같은 정의를 봄 (사고 사례의 교훈)
```

## 2. USE — 리소스의 세 지표

```
대상: 노드 CPU/메모리/디스크/네트워크, 컨테이너 리소스

Utilization:
  CPU: 1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))
  컨테이너: rate(container_cpu_usage_seconds_total[5m]) / limits (조인, 08)
Saturation (★ 진짜 신호인 경우가 많습니다):
  CPU 스로틀: rate(container_cpu_cfs_throttled_periods_total[5m])
             / rate(container_cpu_cfs_periods_total[5m])
  메모리: working_set / limits (1.0 근접 = OOM 임박)
  디스크: predict_linear로 고갈 예측
Errors: OOMKilled(KSM restarts + reason), 네트워크 에러

사용률 vs 포화의 구분:
  CPU 70%인데 스로틀 30% → limits가 낮아 눌리는 중 (사용률만 보면 놓침)
  → "여유 있어 보이는데 느려요"의 단골 원인
```

## 3. 변수(templating) — 하나로 전부

```
변수 정의:
  $namespace: label_values(kube_pod_info, namespace)
  $service:   label_values(http_requests_total{namespace="$namespace"}, service)
  → 연쇄 변수 (namespace 고르면 그 안의 service만)

쿼리에서: {namespace="$namespace", service="$service"}
다중 선택·All: =~"$service" (정규식 매칭으로)

효과: 서비스 N개 = 대시보드 1개
  새 서비스가 생기면? label_values가 자동 반영 — 대시보드 수정 0
  (08의 ServiceMonitor 셀프서비스와 짝: 등록도 자동, 화면도 자동)
```

## 4. 드릴다운과 링크 — 동선의 구현

```
계층:
  L1 개요(온콜의 첫 화면):
    전 서비스 에러율·p99 테이블 (임계 초과 강조 정렬)
    클러스터 수준 포화 (노드·Pending Pod)
  L2 서비스(변수 $service):
    RED 상세 + ★ 배포 마커(annotation — 배포 시각을 그래프에)
    "언제부터"와 "그때 무슨 배포"를 한눈에 (05의 이벤트 문맥)
  L3 인스턴스:
    Pod별 분해 (한 Pod만 이상? 전체?) + USE + 재시작

링크 구현:
  패널 data link: /d/service-dash?var-service=${__field.labels.service}
  → 테이블 행 클릭 = 변수가 전달된 L2로

로그·트레이스로의 점프 (12에서 완성):
  L3에서 "이 Pod의 로그" 링크 (Loki 데이터소스 + 변수 전달)
  exemplar 지원 시 그래프 점 → trace 점프
```

## 5. 대시보드 as code — 프로비저닝

```
방법 (kube-prometheus-stack의 Grafana):
  ① 대시보드 JSON을 ConfigMap에 (label: grafana_dashboard: "1")
  ② Grafana sidecar가 라벨 달린 CM을 감시 → 자동 로드
  ③ CM은 Git에서 (GitOps, cncf 14) — PR 리뷰·이력·복구

운영 관례:
  UI 수정은 실험 → 확정되면 JSON export → Git 커밋 (UI는 초안, Git이 진실)
  대시보드 uid 고정 (링크 안정성)
  json에서 datasource를 변수로 (환경 간 이식)

커뮤니티 대시보드:
  grafana.com의 공개 대시보드(node-exporter full 등) — 좋은 출발점
  단 그대로 쓰면 "남의 질문의 답" — 우리 질문에 맞게 다듬는 것까지
```

## 6. 안티패턴 사전

```
① 그래프 벽: 40패널 — 질문 없이 나열 → 계층·동선으로 분리
② 평균의 함정: avg 지연 — p99를 가립니다 (03) → 분위수 필수
③ counter 원값 플롯: 우상향 직선 (03) → rate
④ 무맥락 숫자: "CPU 3.2" — 한계 대비인가요? → 비율·임계선·색
⑤ 인스턴스별 알록달록 40선: 개별 Pod 선이 의미 있나요? → 집계 + 이상치만
⑥ 과도한 실시간(5s 갱신): 부하만 — 조사용은 30s~1m이면 충분
⑦ 클릭 온리 대시보드: 유실·불일치 (5절) → as code
```

## 7. 소스/도구에서 확인하기

- RED: Tom Wilkie / USE: Brendan Gregg의 방법론 원문
- Grafana provisioning·templating 문서
- kube-prometheus-stack 내장 대시보드 (뜯어보며 배우기 좋음)

## 요약 카드

| 질문 | 답 |
|------|----|
| 대시보드의 목적? | 그래프 벽 X — "누가 어떤 질문으로 오는가"의 조사 동선 |
| RED? | Rate·Errors(비율)·Duration(분위수) — 서비스의 증상 |
| USE? | Utilization·Saturation·Errors — 리소스의 눌림 (포화가 진짜 신호) |
| RED↔USE 동선? | RED에서 증상 감지 → USE(원인 후보)·트레이스로 |
| 변수? | $namespace·$service 연쇄 — 대시보드 1개가 전 서비스 (자동 반영) |
| 드릴다운? | L1 개요→L2 서비스(배포 마커)→L3 Pod→로그/트레이스 링크 |
| as code? | JSON→CM(라벨)→sidecar 로드, Git이 진실 (UI는 초안) |
| 안티패턴? | 그래프 벽·평균·counter 원값·무맥락·40선·과실시간·클릭 온리 |
