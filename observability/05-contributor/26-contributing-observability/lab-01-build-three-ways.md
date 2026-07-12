# Lab 01 — 세 갈래 빌드와 개발 루프

> fluent-bit(C), exporter(Go), OTel Collector(ocb)를 실제로 빌드하고, 그중 하나를 kind의 실습 구성에서 "내 빌드"로 교체해 개발 루프를 완주합니다. 빌드가 되는 순간 심리적 벽이 무너집니다.

## 0. 준비

```bash
# 도구: git, docker, Go(1.22+), cmake·gcc(fluent-bit용 — 선택)
go version && docker --version
```

## 1. 갈래 ① — fluent-bit 빌드 (C 툴체인이 있다면)

```bash
git clone --depth 1 https://github.com/fluent/fluent-bit.git
cd fluent-bit
# (CONTRIBUTING/DEVELOPER_GUIDE의 의존성 설치 후)
cmake -B build -S . -DCMAKE_BUILD_TYPE=Release
cmake --build build -j4
./build/bin/fluent-bit --version
# Fluent Bit v4.x   ← ★ 내가 빌드한 그 도구!

# 코드 지도 확인 — 06의 theory가 코드로
ls plugins/ | head          # in_tail, filter_kubernetes, out_*...
grep -r "multiline" plugins/in_tail/ --include="*.c" -l | head -3
# → 06에서 쓴 cri 파서·tail의 실제 구현 위치를 눈으로
cd ..
```

(C 환경이 어려우면 컨테이너 빌드: `docker build -f dockerfiles/Dockerfile .` — 절차는 저장소 문서 기준. 이 갈래는 "지도 확인"까지로도 충분합니다.)

## 2. 갈래 ② — 미니 exporter를 처음부터 (Go — 자기 영토의 스캐폴드)

03·08의 지식으로 "우리 시스템" exporter의 뼈대를 만듭니다:

```bash
mkdir my-exporter && cd my-exporter
go mod init example.com/my-exporter
go get github.com/prometheus/client_golang/prometheus \
       github.com/prometheus/client_golang/prometheus/promhttp

cat > main.go <<'EOF'
package main

import (
        "net/http"
        "github.com/prometheus/client_golang/prometheus"
        "github.com/prometheus/client_golang/prometheus/promhttp"
)

// 가상의 "우리 시스템" 상태를 노출하는 Collector (03의 규율로 설계)
type myCollector struct {
        queueDepth *prometheus.Desc
        jobsTotal  *prometheus.Desc
}

func newMyCollector() *myCollector {
        return &myCollector{
                queueDepth: prometheus.NewDesc("mysys_queue_depth",
                        "Current queue depth.", []string{"queue"}, nil),          // gauge
                jobsTotal: prometheus.NewDesc("mysys_jobs_processed_total",
                        "Total processed jobs.", []string{"queue", "status"}, nil), // counter
        }
}
func (c *myCollector) Describe(ch chan<- *prometheus.Desc) {
        ch <- c.queueDepth; ch <- c.jobsTotal
}
func (c *myCollector) Collect(ch chan<- prometheus.Metric) {
        // 실전: 여기서 대상 시스템 API를 조회합니다
        ch <- prometheus.MustNewConstMetric(c.queueDepth, prometheus.GaugeValue, 7, "orders")
        ch <- prometheus.MustNewConstMetric(c.jobsTotal, prometheus.CounterValue, 1234, "orders", "ok")
        ch <- prometheus.MustNewConstMetric(c.jobsTotal, prometheus.CounterValue, 17, "orders", "failed")
}

func main() {
        prometheus.MustRegister(newMyCollector())
        http.Handle("/metrics", promhttp.Handler())
        http.ListenAndServe(":9500", nil)
}
EOF
go build -o my-exporter . && ./my-exporter &
sleep 2
curl -s localhost:9500/metrics | grep mysys
# HELP/TYPE + mysys_queue_depth{queue="orders"} 7 ...
# ★ 03의 노출 형식을 "내 코드"가 만들었습니다!
kill %1; cd ..
```

**설계 자기 점검(03의 규율)** — 타입이 맞나(깊이=gauge, 누적=counter+_total), 라벨이 유한한가(queue·status — user_id 같은 unbounded 없음), 이름에 단위·주체가 있나. 이 점검이 exporter 기여 리뷰에서 오갈 바로 그 대화입니다.

## 3. 갈래 ③ — OTel Collector 커스텀 빌드 (ocb)

```bash
go install go.opentelemetry.io/collector/cmd/builder@latest

cat > builder-config.yaml <<'EOF'
dist:
  name: my-otelcol
  output_path: ./my-otelcol
receivers:
  - gomod: go.opentelemetry.io/collector/receiver/otlpreceiver v0.104.0
processors:
  - gomod: go.opentelemetry.io/collector/processor/batchprocessor v0.104.0
exporters:
  - gomod: go.opentelemetry.io/collector/exporter/debugexporter v0.104.0
EOF
builder --config builder-config.yaml
./my-otelcol/my-otelcol --version 2>/dev/null || ls my-otelcol/
# ★ 컴포넌트 3개만 담긴 "나만의 Collector" — 조립형 빌드의 실체
# (버전은 시점의 최신 안정으로 — 문서 확인)
```

**의미** — contrib의 수백 컴포넌트 중 필요한 것만 담는 이 도구가, 새 컴포넌트 개발 시엔 `replace`로 로컬 모듈을 끼우는 실험실이 됩니다(theory 3절). 11·16에서 쓴 Collector의 "정체"가 이 조립의 산물이었습니다.

## 4. 개발 루프 완주 — 내 빌드를 kind에

갈래 ②의 exporter로 루프를 닫습니다:

```bash
# 컨테이너화 → kind 로드 → 08의 수집 체계에 등록
cd my-exporter
cat > Dockerfile <<'EOF'
FROM golang:1.22 AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 go build -o /my-exporter .
FROM gcr.io/distroless/static
COPY --from=build /my-exporter /my-exporter
ENTRYPOINT ["/my-exporter"]
EOF
docker build -t my-exporter:dev .
kind create cluster --name contrib
kind load docker-image my-exporter:dev --name contrib

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-exporter
  labels: { app: my-exporter }
spec:
  replicas: 1
  selector:
    matchLabels: { app: my-exporter }
  template:
    metadata:
      labels: { app: my-exporter }
    spec:
      containers:
        - name: my-exporter
          image: my-exporter:dev
---
apiVersion: v1
kind: Service
metadata:
  name: my-exporter
  labels: { app: my-exporter }       # ServiceMonitor selector가 보는 라벨
spec:
  selector: { app: my-exporter }
  ports:
    - port: 9500
EOF
cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: { name: my-exporter, labels: { release: monitoring } }
spec:
  selector: { matchLabels: { app: my-exporter } }
  endpoints: [{ port: "9500", interval: 15s }]
EOF
sleep 90
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
sleep 3
curl -s 'localhost:9090/api/v1/query?query=mysys_queue_depth' | grep -o '"value":\[[^]]*\]'
# ★ 내가 만든 메트릭이 08의 체계로 수집되어 PromQL로 조회됩니다!
kill %1
```

**루프의 완성** — 코드(내 것) → 빌드 → 이미지 → kind → ServiceMonitor(08) → PromQL 검증. 이 파트에서 수십 번 밟은 동선의 주어가 "남의 도구"에서 **"내 코드"**로 바뀌었습니다 — 기여의 개발 루프가 이미 손에 있습니다.

## 5. 정리

```bash
# 클러스터는 lab-02에서 계속 (검증 환경으로)
echo "첫 기여 제출은 lab-02에서"
```

## 정리

- 세 갈래 빌드 완료: C(fluent-bit — 코드 지도 확인), Go(exporter — 처음부터), ocb(조립형)
- exporter 스캐폴드에 03의 규율(타입·라벨·이름)을 직접 적용 — 리뷰 대화의 예행
- ocb = 경량 배포판이자 컴포넌트 개발의 실험실
- 개발 루프의 주어 전환: 남의 도구 → 내 코드 — 같은 동선(빌드→kind→08→검증)
- **★ 빌드가 되는 순간, "저 코드"는 "내가 고칠 수 있는 코드"가 됩니다**
