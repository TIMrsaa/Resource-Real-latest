# Lab 02 — 5개 서비스에 메트릭 적용

> **🌱 핵심 개념 미리보기**
> - **HTTP 서비스 (Gin)**: middleware 한 줄로 RED 자동 수집
> - **HTTP 서비스 (net/http)**: 직접 wrap 함수로 같은 일
> - **Worker 서비스 (SQS / Kafka)**: HTTP 가 없음 → 직접 메시지 처리 시점에 메트릭 기록
> - **gRPC 서비스**: 별도 interceptor 라이브러리 (RED 의 gRPC 변형)
> - **/metrics 노출**: 별도 포트 (9090) — main 서비스 포트와 분리해 ALB / scrape 분리

## 1. order-service (Gin)

`scenarios/order-service/main.go` 의 router 셋업 부분 수정:

```go
package main

import (
    "log/slog"
    "net/http"

    "github.com/finn/eks-study/order-service/handler"
    "github.com/finn/eks-study/shared/config"
    "github.com/finn/eks-study/shared/logger"
    "github.com/finn/eks-study/shared/metrics"
    "github.com/gin-gonic/gin"
)

func main() {
    log := logger.New("order-service")
    port := config.GetString("PORT", "8080")

    r := gin.New()
    r.Use(gin.Recovery())
    r.Use(metrics.GinMiddleware("order-service"))   // ← 한 줄 추가
    h := handler.New()
    r.POST("/orders", h.Create)
    r.GET("/orders/:id", h.Get)
    r.GET("/healthz", func(c *gin.Context) { c.Status(http.StatusOK) })

    go func() {
        mux := http.NewServeMux()
        mux.Handle("/metrics", metrics.Handler())
        if err := http.ListenAndServe(":9090", mux); err != nil {
            log.Error("metrics server failed", "err", err)
        }
    }()

    log.Info("starting", "port", port)
    if err := r.Run(":" + port); err != nil {
        slog.Error("server failed", "err", err)
    }
}
```

> **🧠 왜 /metrics 를 별도 goroutine + 별도 포트?**
> 1. **보안**: 메트릭은 내부용 — ALB 가 8080 만 노출, 9090 은 ServiceMonitor (클러스터 내부) 만 접근
> 2. **분리**: 메트릭 scrape 가 메인 트래픽에 영향 X (별도 listener)
> 3. **관례**: kube-prometheus-stack 표준 — Service 의 두 번째 port 로 metrics 노출
>
> Service 정의에선:
> ```yaml
> ports:
>   - name: http      # 8080
>   - name: metrics   # 9090 ← ServiceMonitor 가 이 이름 매칭
> ```

> **🧠 `gin.Recovery()` + middleware 순서**
> Recovery 가 먼저 등록되면 panic 발생 시 stack trace 잡고 500 응답.
> middleware 가 그 위 (`Use` 순서대로) → metrics 가 panic 후 정상 측정 (code=500).
>
> 만약 metrics 를 먼저 두면 panic 이 metrics 코드로 전파되어 메트릭 자체 실패 → 측정 누락.
> **Recovery 는 항상 첫 번째**.

## 2. frontend (net/http)

frontend 는 Gin 이 아니라 net/http 사용. middleware 도 net/http 형태로:

`scenarios/frontend/main.go`:
```go
package main

import (
    "net/http"
    "strconv"
    "time"

    "github.com/finn/eks-study/frontend/handler"
    cfg "github.com/finn/eks-study/shared/config"
    "github.com/finn/eks-study/shared/logger"
    "github.com/finn/eks-study/shared/metrics"
)

// statusRecorder for net/http
type statusRecorder struct {
    http.ResponseWriter
    code int
}

func (r *statusRecorder) WriteHeader(code int) {
    r.code = code
    r.ResponseWriter.WriteHeader(code)
}

func instrument(next http.HandlerFunc, route string) http.HandlerFunc {
    httpReq := metrics.Counter("http_requests_total", "...", []string{"service","method","path","code"})
    httpDur := metrics.Histogram("http_request_duration_seconds", "...", []string{"service","method","path"}, nil)

    return func(w http.ResponseWriter, r *http.Request) {
        rec := &statusRecorder{ResponseWriter: w, code: 200}
        start := time.Now()
        next(rec, r)
        d := time.Since(start).Seconds()
        httpReq.WithLabelValues("frontend", r.Method, route, strconv.Itoa(rec.code)).Inc()
        httpDur.WithLabelValues("frontend", r.Method, route).Observe(d)
    }
}

func main() {
    log := logger.New("frontend")
    port := cfg.GetString("PORT", "8080")

    h, err := handler.New("templates/*.html")
    if err != nil { log.Error("template parse", "err", err); return }

    mux := http.NewServeMux()
    mux.HandleFunc("/", instrument(h.Index, "/"))
    mux.HandleFunc("/healthz", instrument(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) }, "/healthz"))
    mux.Handle("/metrics", metrics.Handler())

    log.Info("frontend starting", "port", port)
    if err := http.ListenAndServe(":"+port, mux); err != nil {
        log.Error("listen", "err", err)
    }
}
```

> 위 instrument 헬퍼는 매번 새 메트릭을 등록하지 않도록 init 또는 변수로 빼는 게 더 좋음 (학습용 단순화).

> **🧠 `statusRecorder` 가 왜 필요한가?**
> net/http 의 `http.ResponseWriter` 는 응답 코드를 보존 안 함 (`WriteHeader` 호출 후 잊음).
> 메트릭은 status code 가 필요 (`code="500"` 라벨) → 우리가 직접 wrap 해서 가로챔.
>
> Gin 은 `c.Writer.Status()` 로 자동 제공 — 그래서 middleware 한 줄로 끝남.
> net/http 는 boilerplate 더 필요 — Go 표준의 한계.

> **🧠 `route` 를 함수 인자로 명시 전달**
> Gin 의 `c.FullPath()` 같은 자동 라우트 패턴이 net/http 엔 없음.
> 그래서 등록 시 route 문자열을 명시: `instrument(handler, "/users/:id")`.
>
> 함정: `r.URL.Path` 그대로 라벨에 쓰면 cardinality 폭발. 반드시 패턴 또는 그룹핑 ("/users/:id", "/static/*").

## 3. payment-service (SQS Worker)

HTTP 가 없으니 RED 가 아니라 **워커 메트릭**:
- 처리한 메시지 수 (Counter)
- 실패한 메시지 수 (Counter)
- 메시지 처리 시간 (Histogram)
- 큐 폴링 빈도 (Gauge)

`scenarios/payment-service/main.go`:
```go
import (
    // ...
    "github.com/finn/eks-study/shared/metrics"
)

var (
    msgsTotal = metrics.Counter("payment_messages_total", "Processed messages",
        []string{"result"})    // result: success / fail
    msgDuration = metrics.Histogram("payment_processing_seconds", "Per-message processing",
        []string{}, []float64{0.001, 0.01, 0.1, 0.5, 1, 5, 10})
)

func main() {
    // ... existing setup ...

    c.Handler = func(ctx context.Context, payload []byte) error {
        start := time.Now()
        var msg map[string]any
        err := json.Unmarshal(payload, &msg)
        if err != nil {
            msgsTotal.WithLabelValues("fail").Inc()
            return err
        }
        log.Info("processed payment", "msg", msg)
        msgsTotal.WithLabelValues("success").Inc()
        msgDuration.WithLabelValues().Observe(time.Since(start).Seconds())
        return nil
    }
    // ...
}
```

> **🧠 Worker 의 RED 변형 — Throughput / Errors / Duration**
> HTTP 의 RED 와 일대일 매핑:
> | HTTP RED | Worker 변형 |
> |---------|------------|
> | Rate (RPS) | **Throughput** (msg/s) — `rate(payment_messages_total[1m])` |
> | Errors (5xx 비율) | **Error ratio** — `rate(...{result="fail"}) / rate(...total)` |
> | Duration (p99 latency) | **Processing time** — `histogram_quantile(0.99, rate(payment_processing_seconds_bucket[5m]))` |
>
> 추가로 worker 만의 메트릭:
> - **Queue lag** (메시지가 큐에 쌓인 시간) — KEDA 의 scale 트리거 (Module 13)
> - **In-flight messages** — 동시 처리 중

> **🧠 bucket 경계 선택**
> SQS 메시지 처리 시간 분포 예측: 1ms (단순 처리) ~ 5s (외부 API 호출 포함).
> bucket 을 그 분포에 맞춰: `[0.001, 0.01, 0.1, 0.5, 1, 5, 10]`.
>
> 너무 좁은 bucket (0.001~0.01 만) → 모든 데이터가 마지막 bucket → quantile 계산 무의미.
> 너무 넓은 bucket → 분위수 정확도 떨어짐.
>
> **법칙**: p99 가 들어갈 bucket 이 끝에서 2~3번째여야 정확.

## 4. notification-service (Kafka Worker)

같은 패턴 — 워커 메트릭:
```go
var (
    notifTotal = metrics.Counter("notification_messages_total", "Sent notifications",
        []string{"result"})
    notifDuration = metrics.Histogram("notification_processing_seconds", "Per-message",
        []string{}, []float64{0.001, 0.01, 0.1, 0.5, 1, 5})
)
```

> **🧠 Kafka 워커의 추가 메트릭 후보**
> - **`kafka_consumer_lag{topic, partition}`**: 안 읽은 메시지 수 (consumer lag) — Kafka client 가 자동 노출하는 경우 많음
> - **partition 별 처리율** — 라벨에 `partition` 추가
>
> 단, partition 수가 많으면 (100+) cardinality 주의. 보통 `topic` 까지만 라벨로.

## 5. user-service (gRPC)

gRPC 는 라이브러리가 다름. Prometheus interceptor 사용 (v1 패키지가 가장 안정):
```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "${REPO_ROOT}/scenarios/user-service"
go get github.com/grpc-ecosystem/go-grpc-prometheus
```

`main.go`:
```go
import (
    grpcprom "github.com/grpc-ecosystem/go-grpc-prometheus"
)

func main() {
    // ...
    s := grpc.NewServer(
        grpc.ChainUnaryInterceptor(grpcprom.UnaryServerInterceptor),
        grpc.ChainStreamInterceptor(grpcprom.StreamServerInterceptor),
    )
    pb.RegisterUserServiceServer(s, server.New())
    grpcprom.Register(s)    // 메트릭 초기 0 으로 등록
    // ...
}
```

→ 자동으로 `grpc_server_handled_total`, `grpc_server_handling_seconds_bucket` 등 노출.

> **🧠 `grpcprom.Register(s)` 의 의미 — initial 0 메트릭**
> Prometheus 의 `rate()` 는 시계열의 **마지막 두 점** 을 비교. 첫 호출이 들어오기 전엔 시계열 자체 없음 → rate=NaN.
>
> `Register(s)` 는 등록된 모든 메서드의 메트릭을 **초기 0 으로** 노출 → 첫 호출 전에도 메트릭 존재 → 알람/대시보드 안정.
>
> **interceptor 패턴**: gRPC 의 middleware 와 동일. `Unary` (1요청 1응답) 와 `Stream` (지속 연결) 두 종류 모두 등록 필요.

> **🧠 gRPC 메트릭의 RED 매핑**
> | RED | gRPC 메트릭 |
> |-----|------------|
> | Rate | `rate(grpc_server_handled_total[1m])` |
> | Errors | `grpc_code` 라벨 (`OK`, `Internal`, `NotFound` 등) — HTTP 의 5xx 와 다른 분류 |
> | Duration | `grpc_server_handling_seconds_bucket` |
>
> 함정: HTTP 의 200/500 처럼 단순 분류 X. `grpc_code != "OK"` 이 모두 에러는 아님 (NotFound 는 정상 흐름일 수 있음).
> 알람 시 비즈니스 의미별 코드 정의 필수.

## 6. 빌드 + 테스트

```bash
cd "${REPO_ROOT}/scenarios"
make test
make build
```

## 7. 도커 이미지 재빌드 + ECR 푸시

```bash
make docker
make ecr-push
```

## 8. EKS 의 워크로드 재배포

```bash
kubectl rollout restart deploy -n order
```

> **🧠 `rollout restart` 의 동작**
> 새 ReplicaSet 만들고 점진적 롤링 (RollingUpdate strategy). 기본값으로 한 번에 25% 교체.
> 같은 image 라도 PodSpec 의 annotation 갱신 → Pod 가 새로 만들어짐.
>
> 운영에선 `kubectl rollout status deploy/<name>` 로 진행 모니터링. 실패 시 `kubectl rollout undo` 로 즉시 롤백.

## 9. 메트릭 노출 검증

```bash
# Pod 내부에서 /metrics 확인
POD=$(kubectl get pods -n order -l app.kubernetes.io/name=order-service -o name | head -1)
kubectl exec -n order $POD -- wget -qO- localhost:9090/metrics | grep -E '^http_requests_total|^http_request_duration_seconds_bucket' | head -10
```

기대:
```
http_requests_total{code="200",method="POST",path="/orders",service="order-service"} 5
http_request_duration_seconds_bucket{le="0.005",method="POST",path="/orders",service="order-service"} 3
...
```

> **🧠 검증 흐름 — Pod /metrics → ServiceMonitor → Prometheus**
> 위 명령은 **Pod 자체** 가 메트릭 노출하는지 확인.
> 다음 단계는 **Prometheus 가 받았는지** — Module 19 의 /targets 페이지.
>
> 둘 중 어디서 막히는지 명확히 분리해 진단:
> 1. Pod /metrics 직접 호출 OK + Prometheus targets 에 안 나옴 → ServiceMonitor / selector 문제
> 2. Pod /metrics 자체 비어있음 → 앱 코드 / middleware 미등록 문제

## 10. Prometheus 에서 새 메트릭 쿼리

http://localhost:9090/graph

```promql
sum by (service, path) (rate(http_requests_total[1m]))
histogram_quantile(0.99, sum by (le, service, path) (rate(http_request_duration_seconds_bucket[5m])))
```

→ Module 20 의 recording rule 들이 이제 실제 데이터 채워짐.

> **🧠 메트릭 → 레코딩 룰 → 대시보드 → 알람의 흐름 완성**
> 이 lab 으로 PART-5 의 핵심 사이클 완성:
> ```
>   1. 앱 (이 lab)              → /metrics 노출
>   2. ServiceMonitor (M19)     → Prometheus 가 자동 scrape
>   3. Recording rule (M20)     → 비싼 쿼리 사전 계산
>   4. Grafana 대시보드 (M22)   → recording 메트릭 시각화
>   5. Alert rule (M20, M23)    → SLO 위반 시 알람
> ```
> 각 단계가 독립 — 한 단계만 바꿔도 다른 단계 영향 X (느슨한 결합).

## 학습 확인

1. payment-service 의 메트릭이 RED 와 다른 이유 (왜 워커는 다름)?
2. gRPC 의 status code 가 HTTP 와 다른 점 (메트릭 라벨 관점)?
3. 동일한 메트릭 이름으로 서비스 별 다른 라벨 쓰는 게 좋을까, 별도 메트릭이 좋을까?

> **힌트**:
> 1. HTTP 는 동기 (요청 → 응답), 워커는 비동기 (메시지 ← 큐). RPS 의 의미가 다름. 큐 lag 같은 워커 고유 메트릭 추가 필요.
> 2. HTTP 는 5xx=서버에러로 단순. gRPC code 는 12종 이상 (Internal, Unavailable, DeadlineExceeded, NotFound 등). 일부는 정상 흐름이라 "에러" 정의가 비즈니스마다 다름.
> 3. 같은 이름 + service 라벨 권장 — 통합 PromQL 쉬움. 단, 라벨 set 이 서비스마다 다르면 vector matching 깨짐 → shared/metrics 표준화 필수.

다음: [quiz.md](./quiz.md)
