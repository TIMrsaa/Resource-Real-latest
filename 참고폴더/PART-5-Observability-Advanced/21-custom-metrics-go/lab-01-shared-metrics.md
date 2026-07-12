# Lab 01 — shared/metrics 확장

목표: `scenarios/shared/metrics/metrics.go` 를 RED 메트릭 자동 노출하도록 확장.

> **🌱 핵심 개념 미리보기**
> - **Instrumentation**: 앱 코드에 메트릭 수집 로직 심기. "관찰 가능하게 만들기"
> - **shared/metrics 패턴**: 모든 서비스가 같은 메트릭 정의를 import → 라벨/이름 일관성
> - **Middleware**: HTTP 요청마다 자동 실행되는 함수. 메트릭 수집의 표준 위치
> - **client_golang**: Prometheus Go SDK. Counter/Gauge/Histogram 객체 + /metrics handler 제공
> - **promauto**: Counter/Gauge 등록 자동화 (`MustRegister` 자동 호출)
>
> **shared 패키지로 묶는 이유**:
> ```
>   서비스마다 메트릭 따로 정의 → 라벨 이름 (service vs svc), bucket 경계 다름 → 통합 분석 불가
>   shared 패키지 → 한 곳에서 정의, 모두 import → PromQL 한 줄로 전체 SLI
> ```

## 1. 현재 코드 확인

```bash
# 본 저장소 루트(어디서 git clone 했든)를 자동 감지
REPO_ROOT="$(git rev-parse --show-toplevel)"
cat "${REPO_ROOT}/scenarios/shared/metrics/metrics.go"
```

기대 (P0 에서 만든 단순 버전):
```go
package metrics

import (
    "net/http"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

func Handler() http.Handler {
    return promhttp.Handler()
}
```

> **🧠 `promhttp.Handler()` 가 하는 일**
> 등록된 모든 Collector (Counter/Gauge/Histogram) 의 현재 값을 텍스트 노출 형식으로 응답.
> 별도 데이터 저장소 없음 — 매 호출마다 메모리의 메트릭 객체에서 즉시 직렬화.
>
> 그래서 **앱 프로세스 재시작 = 모든 메트릭 0 으로 리셋** (Counter 도). Prometheus 가 이를 감지해 `rate()` 계산 시 reset 보정.

## 2. 새 코드로 교체

본 모듈의 `manifests/shared-metrics-rps.go` 를 그대로 복사:

```bash
cp "${REPO_ROOT}/PART-5-Observability-Advanced/21-custom-metrics-go/manifests/shared-metrics-rps.go" \
   "${REPO_ROOT}/scenarios/shared/metrics/metrics.go"
```

> **🧠 새 코드가 추가하는 핵심 기능**
> - **`GinMiddleware(serviceName)`**: Gin 의 `Use()` 에 등록 → 모든 요청 자동 계측
>   - `http_requests_total{service, method, path, code}` Counter 증가
>   - `http_request_duration_seconds_bucket{...}` Histogram observe
>   - `http_in_flight_requests{service}` Gauge (요청 중 = +1, 끝나면 -1)
> - **`Counter(name, help, labels)`**: 헬퍼 — 사용자 정의 메트릭 손쉽게 생성
> - **`Histogram(name, help, labels, buckets)`**: 같은 패턴 (buckets 가 nil 이면 기본값)

## 3. 의존성 추가 (gin)

shared 가 gin import 하게 됨:
```bash
cd "${REPO_ROOT}/scenarios/shared"
go get github.com/gin-gonic/gin
```

> **🧠 shared 가 gin 에 의존하면 안 좋지 않나?**
> 일반론: shared 는 의존성 최소화가 원칙.
> 하지만 본 프로젝트 모든 HTTP 서비스가 Gin → 의존성 통일 OK. (frontend 는 net/http 라 별도 헬퍼 사용 — Lab 02 에서)
>
> 더 깔끔한 패턴: `metrics/` (코어), `metrics/gin/` (Gin 어댑터) 분리. 학습용으론 단일 패키지 유지.

## 4. 단위 테스트 추가

`scenarios/shared/metrics/metrics_test.go`:
```go
package metrics

import (
    "io"
    "net/http"
    "net/http/httptest"
    "strings"
    "testing"

    "github.com/gin-gonic/gin"
)

func TestGinMiddlewareRecordsMetrics(t *testing.T) {
    gin.SetMode(gin.TestMode)
    r := gin.New()
    r.Use(GinMiddleware("test-service"))
    r.GET("/hello/:name", func(c *gin.Context) { c.String(200, "ok") })

    w := httptest.NewRecorder()
    req := httptest.NewRequest("GET", "/hello/world", nil)
    r.ServeHTTP(w, req)

    if w.Code != 200 {
        t.Fatalf("expected 200, got %d", w.Code)
    }

    // /metrics 호출하여 우리 메트릭이 노출되는지
    mw := httptest.NewRecorder()
    Handler().ServeHTTP(mw, httptest.NewRequest("GET", "/metrics", nil))
    body, _ := io.ReadAll(mw.Body)
    text := string(body)

    if !strings.Contains(text, `http_requests_total{`) {
        t.Errorf("expected http_requests_total in metrics output")
    }
    if !strings.Contains(text, `service="test-service"`) {
        t.Errorf("expected service label")
    }
    if !strings.Contains(text, `path="/hello/:name"`) {
        t.Errorf("expected route pattern as path label, got body:\n%s", text[:min(2000,len(text))])
    }
}

func min(a, b int) int { if a < b { return a }; return b }

func TestCounterAndGaugeHelpers(t *testing.T) {
    c := Counter("test_counter", "test", []string{"x"})
    c.WithLabelValues("a").Inc()
    g := Gauge("test_gauge", "test", []string{"y"})
    g.WithLabelValues("b").Set(42)

    h := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { Handler().ServeHTTP(w, r) })
    w := httptest.NewRecorder()
    h.ServeHTTP(w, httptest.NewRequest("GET", "/metrics", nil))
    body, _ := io.ReadAll(w.Body)

    for _, want := range []string{`test_counter{x="a"}`, `test_gauge{y="b"} 42`} {
        if !strings.Contains(string(body), want) {
            t.Errorf("missing: %s", want)
        }
    }
}
```

> **🧠 핵심 검증 포인트 — `path="/hello/:name"`**
> Gin 의 `c.FullPath()` 는 **라우트 패턴** 반환 (`/hello/:name`).
> `c.Request.URL.Path` 는 **실제 URL** (`/hello/world`).
>
> 메트릭 라벨엔 반드시 패턴 사용 — 안 그러면 `/hello/world`, `/hello/foo`, `/hello/bar` 가 각각 다른 시계열 → cardinality 폭발.
>
> **테스트의 의미**: 누군가 실수로 `c.Request.URL.Path` 로 바꿔도 이 테스트가 즉시 실패 → 회귀 방지.

## 5. 테스트 실행

```bash
cd "${REPO_ROOT}/scenarios/shared"
go test ./metrics/... -v
```

기대: 두 테스트 PASS.

> **🧠 테스트가 첫 번째 통합 검증**
> 인스트루멘테이션은 "런타임에 망가져도 앱은 계속 동작" 함 (메트릭만 안 나올 뿐).
> = **운영에서 발견 어려움** (페이지 안 옴, 알람 없음).
>
> 그래서 단위 테스트로 "메트릭이 진짜 노출되는지" 강제 검증. CI 단계에서 잡히도록.

## 6. 빌드 검증

```bash
go build ./...
```

기대: 에러 없음.

## 7. 다른 서비스도 빌드 가능 여부

```bash
cd "${REPO_ROOT}/scenarios"
make test
```

기대: 모든 서비스 테스트 PASS (아직 middleware 적용 전이라 동작은 같음).

> **🧠 이 단계에서 점검하는 것**
> shared/metrics 변경이 다른 서비스 코드를 깨지 않았는지 (API 호환성).
> 새 함수 추가는 안전 (additive). 기존 함수 시그니처 변경은 위험 — 모든 import 사이트 깨짐.
>
> 운영 패턴: shared 변경 시 `go work sync` + 전체 테스트 → 최소한 컴파일 에러는 사전 차단.

## 학습 확인

1. `promauto.NewCounterVec` 와 `prometheus.NewCounterVec` + `MustRegister` 의 차이는?
2. `c.FullPath()` 와 `c.Request.URL.Path` 의 라벨 cardinality 관점 차이는?
3. `inFlight` Gauge 가 RED 패턴의 어디에 해당? (R/E/D 외 추가)

> **힌트**:
> 1. `promauto` 는 NewXxxVec 호출과 동시에 default registry 에 등록. `prometheus.NewXxxVec` 는 객체만 만들고 `MustRegister` 따로 호출 필요. promauto = 한 줄. 명시 등록 = 커스텀 registry 사용 시.
> 2. `FullPath()` = 라우트 패턴 (`/users/:id`) — cardinality 작음. `URL.Path` = 실제 (`/users/123`) — 사용자 수만큼 폭발.
> 3. RED 외 추가 차원 — **Concurrency / Saturation** 의 일부. 동시 처리 중인 요청 수. 큐 적체나 연결 폭증을 미리 감지.

다음: [lab-02-instrument-services.md](./lab-02-instrument-services.md)
