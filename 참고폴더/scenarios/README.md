# Scenarios — MSA 시뮬레이션 앱 (Go)

본 커리큘럼 실습에 사용되는 마이크로서비스 5종 + 공통 라이브러리.
모든 서비스는 **Go**로 작성되었으며, distroless 베이스 이미지로 빌드됩니다.

---

## 왜 5개의 서비스로 쪼갰는가? (학습 의도)

각 서비스는 **EKS에서 배우게 될 패턴 1개씩**을 대표합니다:

| 서비스 | 학습 패턴 | 어디서 배움 |
|--------|----------|------------|
| `order-service` | REST + Pod 스케일링 | Part-2-09, Part-3-12 |
| `payment-service` | SQS Worker + 큐 폭주 시 KEDA 스케일 | Part-3-13, Part-3-14 |
| `user-service` | gRPC 서비스 간 통신 | Part-2-09 |
| `notification-service` | Kafka Consumer + Lag 기반 스케일 | Part-3-13 |
| `frontend` | SSR + Ingress(ALB) 노출 | Part-2-06, Part-2-09 |

**MSA의 본질**: "서비스 간 책임을 명확히 쪼개고, 각자 독립적으로 배포/스케일링한다"

```
       [frontend]
           │
           ▼ HTTP (Ingress/ALB)
  ┌────[order-service]────┐
  │                        │
  ▼ gRPC                   ▼ SQS publish
[user-service]    ─────► AWS SQS ─────► [payment-service]
                                              │
                                              ▼ Kafka publish (시나리오 확장 시)
                                          [Kafka topic]
                                              │
                                              ▼ Kafka consume
                                       [notification-service]
```

---

## 서비스 구성

| 서비스 | 역할 | 프로토콜 | KEDA 트리거 (Part 3) |
|--------|------|----------|----------------------|
| `order-service` | 주문 CRUD | REST (Gin, :8080) | Prometheus / CPU |
| `payment-service` | SQS 메시지 → 결제 처리 | SQS Worker | AWS SQS |
| `user-service` | 사용자 CRUD | gRPC (:50051) | CPU |
| `notification-service` | Kafka topic → 알림 발송 | Kafka Worker | Apache Kafka |
| `frontend` | SSR 페이지 | HTTP (:8080) | - |

`shared/` 모듈은 모든 서비스가 공유: `logger`, `config`, `metrics`.

---

## 폴더 구조

```
scenarios/
├── go.work                       # 멀티 모듈 워크스페이스 (Go 1.18+)
│                                  #   → 5개 서비스 + shared 가 한 작업공간에서 빌드됨
├── Makefile                      # build/test/docker/up/down 한방 명령
├── docker-compose.yml            # 로컬 통합 실행 (kafka, localstack 포함)
├── shared/                       # 공통 라이브러리
│   ├── logger/                   # slog 기반 JSON 로거 (구조화 로그)
│   ├── config/                   # 환경변수 헬퍼 (GetString/GetInt 등)
│   └── metrics/                  # Prometheus 메트릭 등록 + /metrics 핸들러
├── order-service/                # REST API
├── payment-service/              # SQS 워커
├── user-service/                 # gRPC
├── notification-service/         # Kafka 워커
└── frontend/                     # SSR 프론트
```

---

## 모든 서비스가 따르는 공통 패턴

각 서비스의 `main.go` 는 거의 동일한 골격을 가집니다 (12-factor app 원칙):

```go
func main() {
    log := logger.New("서비스명")              // 1. 구조화 로거
    port := config.GetString("PORT", "8080")  // 2. 환경변수로 설정 주입

    // 3. 메인 비즈니스 로직 (HTTP/gRPC 서버 또는 워커)
    setupAndStart(...)

    // 4. 별도 포트(9090)로 메트릭 + 헬스체크 노출
    go func() {
        mux := http.NewServeMux()
        mux.Handle("/metrics", metrics.Handler())  // Prometheus 수집용
        mux.HandleFunc("/healthz", okHandler)       // K8s probe용
        http.ListenAndServe(":9090", mux)
    }()

    // 5. graceful shutdown (SIGTERM 받으면 정리 후 종료)
    ctx, stop := signal.NotifyContext(...)
    defer stop()
}
```

**왜 메트릭 포트(9090) 분리?**
- 비즈니스 트래픽(:8080) 과 모니터링 트래픽(:9090) 격리
- ALB는 :8080만 노출, ServiceMonitor는 :9090만 스크레이프
- 운영 트래픽이 막혀도 헬스체크는 살아있게

**왜 /healthz 인가?**
- K8s readinessProbe / livenessProbe 가 GET /healthz 로 헬스체크
- 200 응답 = 트래픽 받을 준비됨, 실패 = 트래픽 빼거나 재시작

---

## 로컬 실행

### 전체 통합 (docker-compose)

```bash
make docker        # 모든 이미지 빌드
make up            # localstack(SQS) + kafka + 5개 서비스 기동
curl http://localhost:8081/    # frontend
curl http://localhost:8080/orders -X POST \
  -H 'Content-Type: application/json' -d '{"user_id":"u1","amount":100}'
make down          # 정리
```

### 단일 서비스 (go run)

```bash
cd order-service
go run .
```

---

## 테스트

```bash
make test          # 전체 서비스 + shared 테스트
```

각 서비스 안에 `*_test.go` 가 있어 단위 테스트 실행.
core 비즈니스 로직만 테스트, AWS/Kafka 호출은 mock 사용.

---

## ECR 푸시

```bash
make ecr-push      # 또는 ../00-prerequisites/scripts/ecr-push-all.sh
```

EKS 클러스터의 노드 IAM에 ECR pull 권한이 있어야 K8s에서 이미지 가져올 수 있음.
(Part-2-05의 cluster.yaml에 `ECRReadOnly` 정책 자동 부착됨)

---

## 메트릭 엔드포인트

모든 서비스는 `:9090/metrics` 와 `:9090/healthz` 노출.

### Prometheus가 스크레이프하는 방법

1. K8s Service에 `:9090` 포트 + 라벨 `app.kubernetes.io/name=<service>`
2. ServiceMonitor가 그 라벨을 셀렉터로 등록
3. Prometheus Operator가 ServiceMonitor를 보고 자동 스크레이프 설정

```yaml
# ServiceMonitor 예 (Part-5에서 등장)
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: order-service
  endpoints:
    - port: metrics       # Service의 named port "metrics" (=9090)
      interval: 30s
```
