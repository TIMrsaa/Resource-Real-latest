// =============================================================================
// shared-metrics-rps.go — Go 앱에 RED 메트릭을 자동 부착하는 공유 미들웨어
// =============================================================================
// 본 파일은 lab-01 의 참고 코드.
// 실제로는 scenarios/shared/metrics/metrics.go 를 다음 내용으로 교체.
//
// RED 메트릭이란? (서비스 모니터링 3대 지표)
//   R - Rate    : 초당 요청 수 (RPS)
//   E - Errors  : 에러율 (5xx 비율)
//   D - Duration: 응답 시간 분포 (p50/p95/p99)
//
// Prometheus 메트릭 타입 3종 (이 파일에 모두 등장):
//   • Counter   : 단조 증가 (요청 수 같은 누적값). rate() 로 초당 변화 추출
//   • Gauge     : 현재값 (CPU 사용률, in-flight 요청 등). 위아래로 변동 가능
//   • Histogram : 분포 (지연시간 같은). 버킷별 카운터로 저장 → quantile 계산 가능
//
// 사용:
//   r := gin.Default()
//   r.Use(metrics.GinMiddleware("order-service"))   // 모든 요청에 자동 메트릭
//   r.GET("/metrics", gin.WrapH(metrics.Handler())) // /metrics 노출
// =============================================================================

package metrics

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto" // 자동 등록 (NewCounterVec + MustRegister)
	"github.com/prometheus/client_golang/prometheus/promhttp" // /metrics HTTP 핸들러
)

// 표준 RED 메트릭들 — 모든 서비스 공유
// 패키지 변수로 선언 → 모든 핸들러에서 같은 시계열에 기록
var (
	// ── R, E: HTTP 요청 카운터 (라벨에 method/path/code 분리) ──
	httpRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",                                  // 메트릭 이름 (Prometheus naming)
			Help: "HTTP requests grouped by method, path, and code.",
		},
		[]string{"service", "method", "path", "code"}, // ← 라벨 이름들
		// ⚠ 카디널리티 주의: path에 /users/:id 같은 변수 포함되면 폭발!
		//    Gin의 c.FullPath() 가 자동으로 /users/:id 형태로 통합해줌
	)

	// ── D: 응답 시간 히스토그램 (버킷별 카운터) ──
	httpRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name: "http_request_duration_seconds",
			Help: "HTTP request duration distribution.",
			// 버킷: 어느 구간에 들어가는지 카운트
			// le="0.001" 카운터 + le="0.005" 카운터 + ... 식으로 누적 저장
			// histogram_quantile() 로 분위수 계산 시 이 버킷이 분해능 결정
			Buckets: []float64{0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5},
		},
		[]string{"service", "method", "path"}, // code는 보통 안 넣음 (분리하면 카디널리티 ↑)
	)

	// ── 추가 시그널: 동시 처리 중 요청 수 ──
	inFlight = promauto.NewGaugeVec(
		prometheus.GaugeOpts{
			Name: "http_requests_in_flight",
			Help: "Currently in-flight HTTP requests.",
		},
		[]string{"service"},
	)
)

// Handler — /metrics 핸들러 (Prometheus가 긁어가는 엔드포인트)
// promhttp.Handler() 가 등록된 모든 메트릭을 텍스트 포맷으로 노출
func Handler() http.Handler {
	return promhttp.Handler()
}

// GinMiddleware — Gin 라우터에 RED 메트릭 자동 적용
// 모든 요청 전후로 메트릭 갱신
func GinMiddleware(serviceName string) gin.HandlerFunc {
	return func(c *gin.Context) {
		// in-flight ↑ (요청 시작)
		inFlight.WithLabelValues(serviceName).Inc()
		defer inFlight.WithLabelValues(serviceName).Dec() // 응답 끝나면 자동 ↓

		start := time.Now()
		c.Next() // 실제 핸들러 실행
		duration := time.Since(start).Seconds()

		// path 정규화: 매칭된 라우트 패턴 (/users/:id) 사용
		// c.Request.URL.Path 쓰면 /users/123 → 매번 다른 라벨 = 카디널리티 폭발!
		path := c.FullPath()
		if path == "" {
			path = "<unmatched>" // 404 같은 매칭 안 된 요청
		}
		code := strconv.Itoa(c.Writer.Status()) // 200 → "200"
		method := c.Request.Method

		// 카운터 ++
		httpRequestsTotal.WithLabelValues(serviceName, method, path, code).Inc()
		// 히스토그램에 관측값 추가 (해당 버킷 카운터 ++)
		httpRequestDuration.WithLabelValues(serviceName, method, path).Observe(duration)
	}
}

// Counter — 커스텀 Counter 등록 헬퍼
// 비즈니스 메트릭용 (orders_created_total 등)
func Counter(name, help string, labels []string) *prometheus.CounterVec {
	return promauto.NewCounterVec(
		prometheus.CounterOpts{Name: name, Help: help},
		labels,
	)
}

// Gauge — 커스텀 Gauge 등록 헬퍼
// 큐 길이, 활성 사용자 수 등 (위아래로 변동하는 값)
func Gauge(name, help string, labels []string) *prometheus.GaugeVec {
	return promauto.NewGaugeVec(
		prometheus.GaugeOpts{Name: name, Help: help},
		labels,
	)
}

// Histogram — 커스텀 Histogram (기본 bucket 또는 명시)
// 결제 금액 분포, DB 쿼리 시간 분포 등
func Histogram(name, help string, labels []string, buckets []float64) *prometheus.HistogramVec {
	if buckets == nil {
		buckets = prometheus.DefBuckets // 기본 버킷 (.005, .01, .025, ..., 10초)
	}
	return promauto.NewHistogramVec(
		prometheus.HistogramOpts{Name: name, Help: help, Buckets: buckets},
		labels,
	)
}
