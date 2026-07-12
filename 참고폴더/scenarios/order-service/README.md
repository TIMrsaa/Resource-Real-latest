# order-service

REST API 기반 주문 관리 서비스. Part 2~3 실습에서 K8s Deployment, HPA, Karpenter 스케일링 시연에 사용.

---

## 코드 한눈에 보기

```
main.go
  └─ Gin 라우터 셋업 (POST /orders, GET /orders/:id, GET /healthz)
  └─ 별도 고루틴으로 :9090/metrics 노출
  └─ :8080 으로 본 서버 시작

handler/order.go
  └─ Handler struct (in-memory map[string]Order + sync.RWMutex)
  └─ Create: JSON 바디 → uuid 생성 → map 저장
  └─ Get   : URL param :id 로 map 조회
```

**왜 in-memory?**
이 학습용 앱은 데이터베이스를 의도적으로 안 씁니다.
- DB 의존성 없이 EKS의 Pod 라이프사이클 학습에 집중
- Pod 재시작하면 데이터 사라짐 → "Pod는 stateless" 라는 K8s 원칙 체험
- 실제 운영은 RDS/DynamoDB + IRSA로 접근하는 패턴 (별도 모듈에서)

**왜 sync.RWMutex?**
Gin은 요청마다 별도 고루틴으로 핸들러 실행 → map 동시 접근 시 race condition.
- `RLock()` : 읽기는 여러 고루틴이 동시에 가능
- `Lock()`  : 쓰기는 한 고루틴만 (다른 모든 고루틴 블록)

---

## 엔드포인트

| Method | Path | 설명 |
|--------|------|------|
| `POST` | `/orders` | 주문 생성 (JSON body: `{"user_id":"...","amount":...}`) |
| `GET` | `/orders/:id` | 주문 조회 (id는 UUID) |
| `GET` | `/healthz` | 헬스체크 (K8s probe용) |
| `GET` | `:9090/metrics` | Prometheus 메트릭 (별도 포트) |

---

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `PORT` | `8080` | HTTP 리스너 포트 |

K8s에서는 ConfigMap을 envFrom으로 주입하거나 Helm values로 관리.

---

## 로컬 실행

```bash
go run .
# 다른 터미널에서:

# 주문 생성
curl -X POST http://localhost:8080/orders \
  -H 'Content-Type: application/json' \
  -d '{"user_id":"u1","amount":1000}'
# → 응답: {"id":"<uuid>","user_id":"u1","amount":1000}

# 주문 조회 (위 응답의 id로)
curl http://localhost:8080/orders/<uuid>

# 메트릭 확인
curl http://localhost:9090/metrics | head -30
```

---

## 테스트

```bash
go test ./...
```

`handler/order_test.go` 는 httptest.NewRecorder + httptest.NewRequest 패턴으로
HTTP 핸들러를 직접 테스트 (실제 서버 안 띄움).

---

## 도커 빌드 (scenarios/ 루트에서)

```bash
docker build -t eks-study/order-service:latest -f order-service/Dockerfile ..
```

**왜 빌드 컨텍스트가 `..` (scenarios/) 인가?**
order-service 가 `shared/` 모듈을 참조함. shared도 같이 복사 필요.
→ 빌드 컨텍스트가 scenarios 전체 (Dockerfile은 그 안에서 상대경로로 지시)

---

## K8s 배포 시 주요 패턴 (Part-2-09에서 다룸)

```yaml
spec:
  template:
    spec:
      containers:
        - name: app
          ports:
            - {name: http, containerPort: 8080}      # 비즈니스
            - {name: metrics, containerPort: 9090}   # 메트릭
          readinessProbe:
            httpGet: {path: /healthz, port: http}    # 200 OK = 트래픽 받기
          livenessProbe:
            httpGet: {path: /healthz, port: http}    # 200 OK = 살아있음
          env:
            - {name: PORT, value: "8080"}
```

---

## Part 3 KEDA 스케일 트리거

이 서비스는 두 가지 방식으로 스케일링 시연:

- **HTTP RPS** (Prometheus 메트릭 기반): `gin_request_duration_seconds_count` rate
- **CPU 사용률**: requests 대비 % 기준

```yaml
# Part-3-12 prom-scaler.yaml 참고
triggers:
  - type: prometheus
    metadata:
      threshold: "10"               # 10 RPS당 Pod 1개
      query: sum(rate(gin_request_duration_seconds_count[1m]))
```
