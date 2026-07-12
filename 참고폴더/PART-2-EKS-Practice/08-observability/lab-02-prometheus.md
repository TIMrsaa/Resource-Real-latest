# Lab 02 — kube-prometheus-stack 설치

## 학습 확인 포인트

- [ ] Prometheus + Grafana + Alertmanager 가 한 번에 설치됨을 봤다
- [ ] ServiceMonitor CRD 로 scrape 대상이 자동 등록됨
- [ ] Grafana 에서 클러스터 메트릭 시각화

> **🌱 핵심 개념 미리보기**
> - **Prometheus**: 시계열 메트릭 DB + 모니터링. Pull 모델 (Prometheus가 앱의 /metrics를 긁어감)
> - **Grafana**: 시각화 도구. 데이터 소스(Prometheus, CloudWatch 등)에서 쿼리해 대시보드
> - **Alertmanager**: Prometheus의 알람을 받아 라우팅 (Slack/이메일/PagerDuty)
> - **kube-prometheus-stack**: 위 셋을 한 Helm 차트로 묶은 패키지 + K8s용 사전 구성
> - **ServiceMonitor (CRD)**: "이 Service의 Pod에서 메트릭 긁어가라" 선언. Prometheus가 자동 발견
>
> **Pull vs Push 모델**:
> ```
>   Pull (Prometheus): Prometheus → "메트릭 줘!" → 앱 /metrics 응답
>   Push (CloudWatch): 앱 → "메트릭 받아!" → CloudWatch
> ```
> Pull은 앱이 살아있는지 자동 감지 (실패하면 scrape 에러). Push는 단방향이라 단순.

## 1. Helm repo 추가

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

> **`helm repo update`**: 모든 등록된 repo의 최신 차트 메타데이터 fetch. apt update 의 helm 버전.

## 2. 설치

```bash
# 본 lab 시점 stable 버전을 자동으로 선택 (65.x ~ 75.x 범위)
KPS_VERSION=$(helm search repo prometheus-community/kube-prometheus-stack \
  --version '>=65.0.0' -o json | jq -r '.[0].version')

helm install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f manifests/values-prometheus.yaml \
  --version "${KPS_VERSION}"
```

> 정확한 버전은 `helm search repo prometheus-community/kube-prometheus-stack -l | head` 로 확인

> **🧠 `kps` 가 뭔가?**
> Helm release 이름. "kube-prometheus-stack" 줄임. 모든 객체 이름에 prefix 됨 (`kps-grafana`, `kps-prometheus-...`).
> 운영에선 환경별로 (`monitoring-prod`, `monitoring-dev`) 명명.
>
> **`--create-namespace`**: NS 없으면 자동 생성. 운영에선 NS 별도 관리(NetworkPolicy 등) 권장.

```bash
kubectl get pods -n monitoring --watch
```

5~7분 후:
```
NAME                                                     READY  STATUS
alertmanager-kps-kube-prometheus-stack-alertmanager-0   2/2    Running
kps-grafana-xxxxx                                       3/3    Running
kps-kube-prometheus-stack-operator-xxxxx                1/1    Running
kps-kube-state-metrics-xxxxx                            1/1    Running
kps-prometheus-node-exporter-xxxxx                      1/1    Running
prometheus-kps-kube-prometheus-stack-prometheus-0       2/2    Running
```

> **🧠 떠있는 Pod들의 역할**
> | Pod | 역할 |
> |-----|------|
> | `prometheus-...` | 메트릭 저장소. PromQL 쿼리 엔진 (StatefulSet, PV 사용) |
> | `alertmanager-...` | Prometheus 알람 라우팅 (StatefulSet) |
> | `kps-grafana-...` | 시각화 UI (Deployment) |
> | `kps-prometheus-stack-operator` | CRD watch + Prometheus 설정 자동 생성 |
> | `kube-state-metrics` | K8s API 객체를 메트릭으로 변환 (Pod 수, Deployment ready 등) |
> | `prometheus-node-exporter` (DaemonSet) | 노드 OS 메트릭 (CPU, RAM, disk, network) |
>
> **READY 컬럼 `2/2`**: Pod에 컨테이너 2개. Prometheus는 본체 + config-reloader sidecar.

## 3. CRD 확인

```bash
kubectl get crd | grep monitoring.coreos.com
```

기대:
```
alertmanagers, podmonitors, probes, prometheuses, prometheusrules,
servicemonitors, thanosrulers
```

> **🧠 CRD가 있어서 좋은 점**
> 옛날: Prometheus 설정을 한 거대한 ConfigMap에 YAML로 적기 → 변경 시 reload 필요, merge 어려움
> Operator 방식: 작은 CRD 객체로 분할 → 각 팀이 자기 ServiceMonitor만 관리, Operator가 자동 통합
>
> 주요 CRD:
> - `Prometheus`: Prometheus 인스턴스 자체 설정
> - `ServiceMonitor`: scrape 대상 (Service 기반)
> - `PodMonitor`: scrape 대상 (Pod 직접)
> - `PrometheusRule`: 알람/recording 규칙
> - `Alertmanager`: Alertmanager 인스턴스 설정

자동 생성된 ServiceMonitor 들:
```bash
kubectl get servicemonitor -n monitoring
```

## 4. Grafana 접근

```bash
kubectl port-forward -n monitoring svc/kps-grafana 3000:80 &
```

> **🧠 `port-forward` 의 동작**
> 로컬 머신의 3000 포트 → kubectl이 K8s API 서버 → Pod 의 80 포트로 터널링.
> Service의 ClusterIP를 외부에서 접근 가능하게 (=실서비스 노출 X, 디버깅용).
> `&` = 백그라운드 실행. 끝낼 땐 `jobs` 로 확인 후 `kill %1`.

브라우저: http://localhost:3000
- ID: `admin`
- PW: `eks-study-admin`

좌측 → Dashboards 메뉴에 자동으로 import 된 대시보드 다수 (`Kubernetes / Compute Resources / *`).

> **자동 import 의 정체**: Grafana Pod에 sidecar(`grafana-sc-dashboard`) 가 떠있음.
> 이 sidecar가 `grafana_dashboard=1` 라벨이 붙은 ConfigMap을 watch → 자동으로 Grafana에 import.
> kube-prometheus-stack은 K8s 표준 대시보드들을 ConfigMap으로 미리 생성.

## 5. Prometheus UI

```bash
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 &
```

브라우저: http://localhost:9090

쿼리 시도:
```
# 노드 수
count(kube_node_info)

# Pod 수 (네임스페이스별)
sum(kube_pod_info) by (namespace)

# CPU 사용률
sum(rate(container_cpu_usage_seconds_total{namespace="default"}[1m])) by (pod)

# Active alerts
ALERTS{alertstate="firing"}
```

> **🧠 PromQL 핵심 함수 단기간 학습**
> - **`rate(metric[1m])`**: 1분간 초당 평균 변화량 (Counter용. requests_total[1m] = RPS)
> - **`sum by (label)`**: label 단위로 합산
> - **`{key="value"}`**: 라벨 매처 (필터). `=~` 정규식, `!=` 아님, `!~` 정규식 아님
> - **`histogram_quantile(0.99, ...)`**: 히스토그램에서 분위수 (p99 등)
> - **`increase(metric[5m])`**: 5분간 총 증가량 (rate * 시간)
>
> **메트릭 타입 4종**:
> - **Counter**: 단조 증가 (`*_total` 접미사). rate/increase로 변화율 추출
> - **Gauge**: 위아래 변동 (현재 메모리, 큐 길이)
> - **Histogram**: 버킷별 카운터 (응답 시간 분포)
> - **Summary**: 분위수를 클라이언트에서 미리 계산 (덜 권장)

## 6. ServiceMonitor 직접 만들기 (커스텀 앱 메트릭)

본 커리큘럼의 `order-service` 가 `:9090/metrics` 를 노출함. 그것을 Prometheus가 scrape 하도록:

```bash
# (Part 1 미니 프로젝트의 차트 사용. 데모로 임시 배포)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
helm install order-svc \
  ../../PART-1-Kubernetes-Basics/04-rbac-helm/charts/order-service \
  --set image.repository=${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/eks-study/order-service \
  --set image.tag=latest \
  -n monitoring

# ServiceMonitor 추가
cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: order-service
  namespace: monitoring
  labels:
    release: kps    # ← 이 label 이 있어야 prometheus 가 scrape
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: order-service
  endpoints:
    - port: metrics
      path: /metrics
      interval: 15s
EOF

# Prometheus targets 페이지에서 추가됨
# http://localhost:9090/targets → "serviceMonitor/monitoring/order-service" 검색
```

> **🧠 `release: kps` 라벨이 필수인 이유**
> Prometheus 객체에 `serviceMonitorSelector: {matchLabels: {release: kps}}` 가 설정됨.
> = "release=kps 라벨 가진 ServiceMonitor만 보겠다".
> 라벨 없으면 Prometheus가 무시 (scrape 안 함, /targets에 안 나타남).
>
> 운영 패턴: 환경별로 selector 다르게 → 같은 클러스터에 dev/prod 모니터링 분리 가능.

## 7. 정리 (이 lab의 데모만)

```bash
kubectl delete servicemonitor -n monitoring order-service
helm uninstall order-svc -n monitoring
```

(kube-prometheus-stack 자체는 다음 lab 에서 사용. 모듈 끝에 cleanup.)

## 학습 확인 질문

1. ServiceMonitor 의 `release: kps` 라벨이 왜 필요한가?
2. Prometheus 의 `retention: 1d` 의 트레이드오프는?
3. PromQL `rate(...)` 와 `irate(...)` 의 차이는?

> **힌트**:
> 1. Prometheus의 serviceMonitorSelector가 release=kps 매칭. 라벨 없으면 자기 것 아니라 판단해 무시.
> 2. 짧은 보관 = 디스크 비용 ↓, 메모리 ↓. 단점 = 1일 이전 데이터 못 봄. 장기 보관 필요시 Thanos/AMP.
> 3. `rate`: 시간 윈도우 내 평균 변화율 (smooth). `irate`: 마지막 두 점만으로 계산 (즉시 반영, 변동 큼). 그래프엔 rate, 알람엔 짧은 윈도우 rate 권장.

다음: [lab-03-grafana-alert.md](./lab-03-grafana-alert.md)
