# 이론 — 스택 구성, ServiceMonitor, 익스포터 3대장, relabeling, recording rules, PromQL 실전

> **🌱 17세 눈높이 비유: 학교 신문부의 취재 시스템**
> - **Prometheus(신문부)** = 정기적으로 각 반을 돌며 소식을 수집(pull)
> - **수동 운영(취재 명단을 종이에)** = 새 반이 생길 때마다 부장이 명단 수정 — 병목
> - **ServiceMonitor(취재 요청서)** = 각 반이 "우리 반 이 게시판을 취재해 주세요"라고 요청서를 내면 자동으로 취재 순회에 포함 — 셀프서비스
> - **익스포터 3대장** = 시설과(node-exporter: 건물·전기), 교무과(KSM: 학급 편성·정원 현황), 각 반 게시판(cAdvisor: 반별 활동량) — 같은 학교의 다른 관점
> - **relabeling(편집 데스크)** = 취재 온 기사에서 불필요한 신상(나쁜 라벨)을 지우고 제목을 다듬어 보관 — 보관함(TSDB) 폭발 방지
> - **recording rule(주간 요약본)** = 매번 전체 기사를 뒤져 통계 내지 말고, 주간 요약을 미리 만들어 두면 누구나 빨리 봄

---

## 1. kube-prometheus-stack 구성

```
helm 차트 하나에:
  Prometheus Operator     — CRD 감시·설정 생성 (두뇌)
  Prometheus (CRD로 정의) — 서버 본체 (StatefulSet)
  Alertmanager (CRD)      — 알림 라우팅 (10)
  Grafana                 — 대시보드 (09) + 기본 대시보드 내장
  node-exporter (DS)      — 노드 OS 메트릭
  kube-state-metrics      — K8s 오브젝트 상태 메트릭
  기본 ServiceMonitor들    — 컨트롤 플레인·kubelet 자동 수집
  기본 PrometheusRule들    — 잘 만든 알림 세트 (10에서 검토)

CRD 체계 (Operator 패턴, cncf 08):
  Prometheus ──selector──> ServiceMonitor/PodMonitor ──selector──> Service/Pod
       │                                                    (라벨 매칭 사슬!)
       └─ruleSelector──> PrometheusRule
```

## 2. ServiceMonitor — 선언형 스크레이프

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: payment
  labels:
    release: monitoring        # ★ Prometheus의 selector와 일치해야!
spec:
  selector:
    matchLabels:
      app: payment             # 이 라벨의 Service를 찾아
  endpoints:
    - port: metrics            # Service의 포트 "이름" (번호 아님!)
      interval: 30s
      path: /metrics

동작: Operator가 이 CRD를 보고 scrape_config 생성 →
     Service 뒤 엔드포인트(Pod들)를 개별 타깃으로

매칭 사슬 3연쇄 (안 긁힐 때 점검 순서):
  ① Prometheus.spec.serviceMonitorSelector ↔ ServiceMonitor.labels
  ② ServiceMonitor.spec.selector ↔ Service.labels
  ③ endpoints.port(이름) ↔ Service.ports[].name
  → 하나라도 어긋나면 조용히 미수집 (pitfalls 1)

PodMonitor: Service 없이 Pod를 직접 (헤드리스·잡 등)
셀프서비스: 앱 팀이 자기 ns에 ServiceMonitor 배포 → 자동 수집
  (namespaceSelector로 범위 통제 — 멀티테넌시)
```

## 3. 익스포터 3대장 (+α)

```
node-exporter (DaemonSet, :9100):
  node_cpu_seconds_total, node_memory_MemAvailable_bytes,
  node_filesystem_avail_bytes, node_network_*
  → "기계"의 관점 — 노드 디스크 알림(05 카탈로그)의 원천

kube-state-metrics (Deployment):
  kube_pod_status_phase, kube_deployment_status_replicas_available,
  kube_pod_container_status_restarts_total, kube_node_status_condition
  → "K8s 오브젝트"의 관점 — API의 상태를 메트릭으로 번역
  ★ 리소스 사용량이 아닙니다! (Pending 몇 개, 재시작 몇 번 — 상태·개수)

cAdvisor (kubelet 내장, /metrics/cadvisor):
  container_cpu_usage_seconds_total, container_memory_working_set_bytes
  → "컨테이너 사용량"의 관점 (01·03에서 확인한 그것)

+ 앱 메트릭 (ServiceMonitor로 등록하는 우리의 /metrics)
+ 컴포넌트 메트릭 (API 서버·etcd·kubelet — 기본 ServiceMonitor가 수집)

질문→소스 매핑 연습:
  "재시작 많은 Pod?" → KSM(restarts_total)
  "그 Pod가 OOM 직전?" → cAdvisor(working_set vs limits)
  "노드 디스크 예측?" → node-exporter(predict_linear)
  "replicas가 원하는 수보다 적습니다?" → KSM(desired vs available)
```

## 4. relabeling — 수집 시점의 수문

```
두 단계:
  relabelings (스크레이프 전 — 타깃 조작):
    대상 필터(특정 Pod만), 타깃 라벨 추가/변경 (예: team 라벨 부여)
  metricRelabelings (스크레이프 후, 저장 전 — ★ 수문):
    action: drop/keep    — 메트릭 통째로 버림/남김 (정규식)
    action: labeldrop    — 라벨 제거 (카디널리티 원흉 제거)
    action: replace      — 라벨 rename·정규화

예 — 서드파티 익스포터의 나쁜 라벨 통제:
  metricRelabelings:
    - sourceLabels: [__name__]
      regex: "go_gc_.*"          # 필요 없는 런타임 메트릭
      action: drop
    - regex: "pod_template_hash"  # 무의미한 고카디널리티 라벨
      action: labeldrop

★ TSDB에 들어가기 전에 자르는 것이 핵심 — 저장 후 삭제는 늦습니다 (03 사고)
  06의 grep 필터(로그) ↔ metricRelabelings(메트릭): 같은 "소스 수문" 사상
```

## 5. recording rules — 사전 계산

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: service-slis
  labels: { release: monitoring }
spec:
  groups:
    - name: sli.rules
      interval: 30s
      rules:
        - record: service:http_requests:rate5m       # 명명 관례: level:metric:op
          expr: sum by (service) (rate(http_requests_total[5m]))
        - record: service:http_error_ratio:rate5m
          expr: |
            sum by (service) (rate(http_requests_total{code=~"5.."}[5m]))
            / sum by (service) (rate(http_requests_total[5m]))

효과:
  대시보드·알림이 가벼운 조회로 (계산 1회 → 소비 N회)
  일관성: 모두가 같은 정의의 에러율을 봄 (팀마다 다른 쿼리 방지)
  21(SLO): 번레이트 = recording rule 조합이 표준 구현

주의: rule도 시계열을 만듭니다 (많으면 그것대로 비용) — 소비되는 것만
```

## 6. PromQL 실전 패턴 (03의 연장)

```
에러율:  sum(rate(http_requests_total{code=~"5.."}[5m]))
        / sum(rate(http_requests_total[5m]))
p99:    histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
포화:   container_memory_working_set_bytes / on(pod)
        kube_pod_container_resource_limits{resource="memory"}
예측:   predict_linear(node_filesystem_avail_bytes[6h], 4*3600) < 0
없는 것 감지: up == 0  /  absent(up{job="payment"})
  ★ up: 스크레이프 성공 여부 — "타깃이 죽었나"의 1차 신호
증가 감지: increase(kube_pod_container_status_restarts_total[1h]) > 3

조인(라벨 매칭):
  on(라벨) group_left — KSM의 메타(라벨)를 사용량(cAdvisor)에 붙일 때
  예: 사용량을 team별로 — cAdvisor에는 team이 없고 KSM엔 있습니다 → 조인
```

## 7. 소스/도구에서 확인하기

- kube-prometheus-stack: prometheus-community/helm-charts
- Operator CRD: prometheus-operator.dev — ServiceMonitor·PrometheusRule 스펙
- relabeling: prometheus.io/docs (relabel_config)
- cncf 11: TSDB·카디널리티의 물리 (이 모듈의 심화 이론)

## 요약 카드

| 질문 | 답 |
|------|----|
| 스택 구성? | Operator(두뇌)+Prometheus+Alertmanager+Grafana+익스포터들+기본 룰 |
| ServiceMonitor? | 스크레이프 대상의 CRD 선언 — 라벨 매칭 3연쇄(Prom↔SM↔Service) |
| 셀프서비스? | 앱 팀이 자기 ns에 SM 배포 → 자동 수집 (중앙 병목 제거) |
| 3대장 구분? | node-exporter(기계)·KSM(오브젝트 상태)·cAdvisor(컨테이너 사용량) |
| KSM 주의? | 상태·개수의 번역이지 사용량이 아님 |
| relabeling? | 수집 시점 수문 — metricRelabelings로 drop/labeldrop (저장 전!) |
| recording rule? | 비싼 쿼리 사전 계산 — 계산 1회·소비 N회 + 정의 일관성 (21 기반) |
| up 메트릭? | 스크레이프 성공 여부 — 타깃 생사의 1차 신호 |
