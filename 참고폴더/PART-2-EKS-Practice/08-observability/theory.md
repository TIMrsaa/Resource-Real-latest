# 이론 — Observability 3축 + EKS 옵션

> **🌱 Observability = "병원의 진단 도구 3종 세트"**
> Metrics (체온/혈압) — 지금 환자 상태가 어떤가, Logs (진료기록) — 그 순간 무엇을 했는가, Traces (X-ray 동선) — 진료 → 검사 → 약 받기 흐름이 어떻게 흘렀나.
> 한 가지만 봐선 오진이 잦다 — 세 가지를 함께 봐야 빠르고 정확한 진단.

## 1. 관측의 세 가지 축

| 축 | 답하는 질문 | 도구 (오픈소스) | AWS 네이티브 |
|----|-----------|-----------------|--------------|
| **Metrics** | "지금 시스템이 얼마나 바쁘지?" | Prometheus | CloudWatch Metrics, Container Insights |
| **Logs** | "그 순간에 무슨 일이 있었지?" | Loki, Elasticsearch | CloudWatch Logs |
| **Traces** | "이 요청이 어떤 경로로 흘렀지?" | Jaeger, Tempo | AWS X-Ray |

> **🧠 "장애 발생 시 Metrics → Logs → Traces 순서로 본다"**
> Metrics 로 *어디서* 이상이 났는지 좁히고 → Logs 로 *그 시점 무슨 일* 인지 보고 → Traces 로 *왜 그 경로로 흘렀는지* 확인.
> 역순 (Logs 부터) 으로 가면 정보 양에 묻혀 원인까지 못 도달한다.

## 2. EKS 에서 흔히 쓰는 조합

### 2.1 AWS 100% 조합
- Container Insights (메트릭 + 컨테이너/노드 메트릭)
- CloudWatch Logs (Fluent Bit DaemonSet으로 수집)
- AWS X-Ray (트레이스)
- 장점: 셋업 쉬움, AWS 통합
- 단점: 비용 (특히 Logs ingestion), 커스터마이징 한계

### 2.2 오픈소스 100% 조합
- kube-prometheus-stack (Prometheus + Grafana + Alertmanager + node-exporter + kube-state-metrics)
- Loki (로그)
- Tempo / Jaeger (트레이스)
- 장점: 비용 낮음, 강력한 쿼리 (PromQL/LogQL)
- 단점: 직접 운영, 스토리지 관리

### 2.3 하이브리드 (실무 가장 흔함)
- **Prometheus + Grafana**: 메트릭 (cardinality 높음 → Prometheus가 강함)
- **CloudWatch Logs**: Fluent Bit으로 보냄 (로그)
- **X-Ray** 또는 **OpenTelemetry → Tempo/Jaeger**: 트레이스

본 커리큘럼은 **하이브리드** 방향. CloudWatch Container Insights + kube-prometheus-stack 동시 설치.

> **🧠 "AWS 100% 의 진짜 함정은 *Logs* 비용"**
> Container Insights 자체보다 *CloudWatch Logs ingest ($0.50/GB)* 가 청구서를 폭발시킨다.
> 그래서 운영에선 메트릭은 Prometheus, 로그는 *retention 짧게* 또는 S3 export — Logs 만 별도 비용 관리.

## 3. CloudWatch Container Insights 구조

```
EKS Node
  ├─ aws-cloudwatch-metrics (DaemonSet) → CloudWatch Metrics 로 보냄
  ├─ fluent-bit (DaemonSet) → CloudWatch Logs 로 보냄
  └─ amazon-cloudwatch-observability (Operator)  ← 신규 통합 패키지

CloudWatch
  ├─ Container Insights (네임스페이스/Pod/노드 차원의 메트릭)
  ├─ Logs (앱 로그, 컨트롤 플레인 로그)
  └─ Alarms (메트릭 임계값 기반)
```

EKS addon 으로 한 번에 설치:
```bash
eksctl create addon --cluster eks-study --name amazon-cloudwatch-observability \
  --service-account-role-arn <iam-role>
```

> **🧠 "통합 패키지" 가 빠른 시작에 유리하지만 세밀 튜닝은 분리 설치"**
> `amazon-cloudwatch-observability` 는 cloudwatch-agent + fluent-bit + dashboards 를 한 번에 — 학습/PoC 에 최적.
> 다만 fluent-bit 의 input 필터를 세밀하게 만지고 싶다면 분리 설치 + Helm chart 가 더 자유롭다.

## 4. kube-prometheus-stack 구조

```
[Prometheus Operator]
   ├── Prometheus (statefulset)         ← 메트릭 저장 + 쿼리 엔진
   ├── Alertmanager                     ← Alert 라우팅 + 통지
   ├── Grafana (deployment)             ← 시각화
   ├── node-exporter (daemonset)        ← 노드 OS 메트릭
   ├── kube-state-metrics               ← K8s 객체 상태 메트릭
   └── ServiceMonitor / PodMonitor (CRD) ← scrape 대상 정의
```

**ServiceMonitor**: 매니페스트로 Prometheus 가 어떤 Service 의 어떤 포트를 scrape 할지 선언적 정의. Helm 으로 설치한 다른 컴포넌트들이 이 CRD 로 자동 등록.

> **🧠 "ServiceMonitor 가 안 잡힌다면 `release` 라벨부터"**
> kube-prometheus-stack 의 Prometheus 는 default selector 가 `release: kps` — 이 라벨이 없는 ServiceMonitor 는 무시된다.
> 처음 Prometheus 에 새 타겟을 추가할 때 가장 흔한 함정 = label 누락.

## 5. 메트릭 종류 4가지 (Prometheus)

| 타입 | 의미 | 예시 |
|------|------|------|
| Counter | 단조 증가 | `http_requests_total` |
| Gauge | 오르내림 | `goroutines_count`, `memory_bytes` |
| Histogram | 분포 (bucket) | `http_request_duration_seconds_bucket` |
| Summary | 분포 (quantile) | `http_request_duration_seconds{quantile="0.99"}` |

자주 쓰는 PromQL:
```
# 순간 RPS
rate(http_requests_total[1m])

# CPU 사용률 (%)
sum(rate(container_cpu_usage_seconds_total{namespace="default"}[1m])) by (pod)

# 메모리 사용량
sum(container_memory_working_set_bytes{namespace="default"}) by (pod)

# 5xx 비율
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))
```

> **🧠 "Counter 를 그대로 그리지 마라 — `rate()` 가 답"**
> Counter 는 단조 증가라 그대로 그리면 일직선만 보인다.
> 실제 의미 있는 그래프는 *시간당 증가량* (rate/increase) — Prometheus 메트릭의 90% 가 Counter 인 이유는 *rate 가 안전* 하기 때문.

## 6. Grafana 대시보드 패턴

- **Cluster Overview**: 노드 수, Pod 수, CPU/Mem 사용률, 가용성
- **Workload (Namespace)**: NS 별 리소스 사용
- **Workload (Pod)**: 특정 Deployment 의 Pod 별 메트릭
- **Application**: 앱 자체 RPS, 에러율, latency

ID 만 알면 import:
- 315 (Kubernetes cluster monitoring)
- 1860 (Node Exporter Full)
- 7249 (Kubernetes Cluster)

> **🧠 "대시보드는 *직접 만들기* 보다 *import 후 가지치기*"**
> 1860 같은 인기 대시보드는 수십 개 패널이 정교하게 짜여 있다 — 처음부터 자작하는 건 비효율.
> Import → 안 쓰는 패널 삭제 → 우리 라벨 (namespace, env) 추가 정도가 가장 빠른 운영 대시보드 구축법.

## 7. 로그 수집 — Fluent Bit

DaemonSet으로 노드별 1개 Pod:
- `/var/log/containers/*.log` 읽기 (Container Runtime이 stdout/stderr를 여기로 떨어뜨림)
- 파싱 (JSON 자동 인식)
- 외부로 전송 (CloudWatch Logs / Loki / Elasticsearch / Kafka)

CloudWatch Logs Group 구조 (Container Insights):
- `/aws/containerinsights/<cluster>/application` — 앱 로그
- `/aws/containerinsights/<cluster>/host` — 노드 OS 로그
- `/aws/containerinsights/<cluster>/dataplane` — kubelet, 컨테이너 런타임

> **🧠 "앱 로그는 stdout/stderr 로만" — 파일에 직접 쓰지 마라**
> 컨테이너 안에서 파일에 로그를 쓰면 Fluent Bit 이 못 잡고, Pod 가 죽으면 영원히 잃는다.
> 표준출력으로 보내면 Container Runtime 이 `/var/log/containers` 에 저장 → Fluent Bit 이 안전하게 수집.

다음: [lab-01-cloudwatch.md](./lab-01-cloudwatch.md)
