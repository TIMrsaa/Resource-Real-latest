# P0: EKS 학습 커리큘럼 — 기반 구축 (Foundation)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** EKS 학습 커리큘럼의 기반(루트 README, 폴더 스캐폴딩, 사전준비 문서, Go 기반 MSA 시나리오 앱 5종, 레퍼런스 치트시트)을 구축한다.

**Architecture:** `/Users/finn/test/eks-study/` 아래에 모듈화된 폴더 구조 생성. Go 시나리오 앱은 멀티 모듈(`go.work`) + `shared` 공통 라이브러리. 각 서비스는 distroless 멀티스테이지 Dockerfile.

**Tech Stack:** Go 1.22+, Gin (REST), grpc-go, AWS SDK v2 (SQS), segmentio/kafka-go, prometheus/client_golang, html/template, Docker, ECR, AWS CLI v2.

**Spec 참조:** `/Users/finn/test/eks-study/docs/specs/2026-04-25-eks-study-curriculum-design.md`

---

## File Structure

```
/Users/finn/test/eks-study/
├── README.md                                 # [Task 1] 루트 README + 로드맵
├── .gitignore                                # [Task 1]
│
├── 00-prerequisites/                         # [Task 2]
│   ├── README.md
│   ├── 01-aws-account-setup.md
│   ├── 02-local-tools.md
│   ├── 03-cost-guardrails.md
│   ├── 04-ecr-setup.md
│   └── scripts/
│       ├── check-tools.sh
│       ├── setup-budget-alarm.sh
│       └── ecr-push-all.sh
│
├── scenarios/                                # [Task 3~9]
│   ├── README.md                             # [Task 3]
│   ├── go.work                               # [Task 3]
│   ├── docker-compose.yml                    # [Task 9]
│   ├── Makefile                              # [Task 3]
│   ├── shared/                               # [Task 3]
│   │   ├── go.mod
│   │   ├── logger/logger.go
│   │   ├── config/config.go
│   │   └── metrics/metrics.go
│   ├── order-service/                        # [Task 4]
│   │   ├── go.mod
│   │   ├── main.go
│   │   ├── handler/order.go
│   │   ├── handler/order_test.go
│   │   ├── Dockerfile
│   │   └── README.md
│   ├── payment-service/                      # [Task 5]
│   │   ├── go.mod, main.go
│   │   ├── consumer/sqs.go, consumer/sqs_test.go
│   │   ├── Dockerfile, README.md
│   ├── user-service/                         # [Task 6]
│   │   ├── go.mod, main.go
│   │   ├── proto/user.proto
│   │   ├── server/user.go, server/user_test.go
│   │   ├── Dockerfile, README.md
│   ├── notification-service/                 # [Task 7]
│   │   ├── go.mod, main.go
│   │   ├── consumer/kafka.go, consumer/kafka_test.go
│   │   ├── Dockerfile, README.md
│   └── frontend/                             # [Task 8]
│       ├── go.mod, main.go
│       ├── handler/page.go, handler/page_test.go
│       ├── templates/index.html
│       ├── Dockerfile, README.md
│
└── reference/                                # [Task 10]
    ├── cheatsheet-kubectl.md
    ├── cheatsheet-eksctl.md
    ├── cheatsheet-helm.md
    ├── cheatsheet-aws.md
    ├── cost-guardrails.md
    └── links.md
```

---

## Task 1: 루트 스캐폴딩 & README

**Files:**
- Create: `/Users/finn/test/eks-study/README.md`
- Create: `/Users/finn/test/eks-study/.gitignore`

- [ ] **Step 1.1: 빈 폴더 구조 생성**

```bash
cd /Users/finn/test/eks-study
mkdir -p 00-prerequisites/scripts
mkdir -p PART-1-Kubernetes-Basics/{01-core-concepts,02-services-networking,03-config-storage,04-rbac-helm}
mkdir -p PART-2-EKS-Practice/{05-eks-cluster-eksctl,06-vpc-cni-networking,07-storage-irsa,08-observability,09-msa-deploy}
mkdir -p PART-3-Karpenter-KEDA/{10-karpenter-install,11-karpenter-advanced,12-keda-basics,13-keda-event-driven,14-karpenter-keda-combo,15-terraform-iac}
mkdir -p PART-4-Operations/{16-troubleshooting,17-cost-optimization,18-upgrade-strategy}
mkdir -p scenarios/{shared,order-service,payment-service,user-service,notification-service,frontend}
mkdir -p docs/diagrams reference
```

- [ ] **Step 1.2: 루트 README.md 작성**

내용:
- 학습 목표 요약 (spec §1)
- 트랙 표 (spec §2) + 진도 체크리스트 (`- [ ] 모듈 01: ...` 18개)
- 학습 방법 가이드: 각 모듈 진행 순서 (`README.md → theory.md → lab → quiz → cleanup`)
- 사전 준비 → `00-prerequisites/`로 안내
- 비용 가드레일 핵심 3줄 (eksctl delete, Spot 우선, AWS Budgets 50 USD)
- 폴더 구조 트리 (spec §5 그대로)
- 참고 자료 (`reference/links.md`)

검증: `wc -l /Users/finn/test/eks-study/README.md` 결과 100줄 이상.

- [ ] **Step 1.3: .gitignore 작성**

```
# Local secrets
*.pem
*.key
*-credentials.json
.env
.env.local

# Terraform
.terraform/
*.tfstate
*.tfstate.backup
*.tfvars
!example.tfvars

# Go
*.exe
*.test
*.out
vendor/
bin/

# kubeconfig
kubeconfig
*.kubeconfig

# Editor
.vscode/
.idea/
.DS_Store

# Output
*.log
output/
```

- [ ] **Step 1.4: 검증**

```bash
cd /Users/finn/test/eks-study && find . -type d -maxdepth 3 | sort
```

기대: 위 mkdir로 만든 모든 폴더가 존재.

---

## Task 2: 00-prerequisites 작성

**Files:**
- Create: `00-prerequisites/README.md`
- Create: `00-prerequisites/01-aws-account-setup.md`
- Create: `00-prerequisites/02-local-tools.md`
- Create: `00-prerequisites/03-cost-guardrails.md`
- Create: `00-prerequisites/04-ecr-setup.md`
- Create: `00-prerequisites/scripts/check-tools.sh`
- Create: `00-prerequisites/scripts/setup-budget-alarm.sh`
- Create: `00-prerequisites/scripts/ecr-push-all.sh`

- [ ] **Step 2.1: README.md (모듈 개요)**

내용:
- 학습 목표: 본 커리큘럼 진행에 필요한 AWS/로컬 환경을 준비한다
- 진행 순서: 01 → 02 → 03 → 04
- 소요 시간: 1~2시간
- 예상 비용: 0 USD (셋업만, 실제 리소스 미생성)

- [ ] **Step 2.2: 01-aws-account-setup.md**

내용:
- IAM 사용자 생성 (Admin이 아닌 PowerUser + 필요한 IAM 권한 추가)
- AdministratorAccess는 학습 편의상 허용하되 별도 계정 권장 명시
- AWS CLI 자격증명 등록: `aws configure`
- 리전 통일: `ap-northeast-2`
- 검증: `aws sts get-caller-identity` 출력 캡처

- [ ] **Step 2.3: 02-local-tools.md**

설치 가이드 (macOS Homebrew 기준):
```bash
brew install awscli kubectl eksctl helm k9s stern jq yq
brew install --cask docker
brew install go terraform
```

각 도구별 1줄 설명 + 버전 확인 명령:
- `aws --version` (≥ 2.15)
- `kubectl version --client` (≥ 1.29)
- `eksctl version` (≥ 0.170)
- `helm version` (≥ 3.14)
- `terraform version` (≥ 1.7)
- `go version` (≥ 1.22)
- `docker version`

- [ ] **Step 2.4: 03-cost-guardrails.md**

내용:
- AWS Budgets 50 USD 알람 설정 절차 (콘솔 클릭 가이드 + `setup-budget-alarm.sh` 사용)
- "실습 후 반드시 cleanup" 원칙
- 잔존 리소스 체크리스트: NLB/ALB, EBS volumes, EIP, NAT Gateway, EKS 클러스터
- `aws ec2 describe-instances --query 'Reservations[].Instances[?State.Name==\`running\`]'` 같은 점검 명령

- [ ] **Step 2.5: 04-ecr-setup.md**

내용:
- ECR 리포지토리 5개 생성 명령:
```bash
for svc in order-service payment-service user-service notification-service frontend; do
  aws ecr create-repository --repository-name eks-study/$svc --region ap-northeast-2
done
```
- ECR 로그인: `aws ecr get-login-password ... | docker login ...`
- `scripts/ecr-push-all.sh`로 모든 서비스 빌드+푸시 한 번에

- [ ] **Step 2.6: scripts/check-tools.sh 작성**

```bash
#!/usr/bin/env bash
set -euo pipefail

REQUIRED=(aws kubectl eksctl helm terraform go docker jq yq k9s stern)
MISSING=()

for cmd in "${REQUIRED[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    MISSING+=("$cmd")
  fi
done

if (( ${#MISSING[@]} > 0 )); then
  echo "❌ 다음 도구가 설치되지 않았습니다: ${MISSING[*]}"
  echo "→ 02-local-tools.md를 참고해 설치하세요."
  exit 1
fi

echo "✅ 모든 도구가 설치됨"
echo ""
echo "버전:"
aws --version
kubectl version --client --output=yaml | head -3
eksctl version
helm version --short
terraform version | head -1
go version
docker --version
```

`chmod +x`까지 step에 포함.

- [ ] **Step 2.7: scripts/setup-budget-alarm.sh 작성**

```bash
#!/usr/bin/env bash
set -euo pipefail

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
EMAIL="${1:?사용법: $0 <알람-수신-이메일>}"
BUDGET_AMOUNT="${2:-50}"

cat > /tmp/budget.json <<EOF
{
  "BudgetName": "eks-study-budget",
  "BudgetLimit": {"Amount": "${BUDGET_AMOUNT}", "Unit": "USD"},
  "TimeUnit": "MONTHLY",
  "BudgetType": "COST"
}
EOF

cat > /tmp/notifications.json <<EOF
[{
  "Notification": {
    "NotificationType": "ACTUAL",
    "ComparisonOperator": "GREATER_THAN",
    "Threshold": 80,
    "ThresholdType": "PERCENTAGE"
  },
  "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "${EMAIL}"}]
}]
EOF

aws budgets create-budget \
  --account-id "${ACCOUNT_ID}" \
  --budget file:///tmp/budget.json \
  --notifications-with-subscribers file:///tmp/notifications.json

echo "✅ ${BUDGET_AMOUNT} USD 예산 알람 생성 완료 (수신: ${EMAIL})"
```

- [ ] **Step 2.8: scripts/ecr-push-all.sh 작성**

```bash
#!/usr/bin/env bash
set -euo pipefail

REGION="${AWS_REGION:-ap-northeast-2}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
SERVICES=(order-service payment-service user-service notification-service frontend)

aws ecr get-login-password --region "${REGION}" \
  | docker login --username AWS --password-stdin "${REGISTRY}"

cd "$(dirname "$0")/../.."  # → eks-study/
cd scenarios

for svc in "${SERVICES[@]}"; do
  echo "▶ Building ${svc}..."
  docker build -t "${REGISTRY}/eks-study/${svc}:latest" -f "${svc}/Dockerfile" .
  docker push "${REGISTRY}/eks-study/${svc}:latest"
done

echo "✅ 모든 이미지 푸시 완료"
```

- [ ] **Step 2.9: 검증**

```bash
ls /Users/finn/test/eks-study/00-prerequisites/
ls /Users/finn/test/eks-study/00-prerequisites/scripts/
chmod +x /Users/finn/test/eks-study/00-prerequisites/scripts/*.sh
bash /Users/finn/test/eks-study/00-prerequisites/scripts/check-tools.sh
```

기대: 4개 .md + 3개 .sh 존재, check-tools.sh가 정상 종료(또는 누락 도구 안내).

---

## Task 3: scenarios/ 베이스 (go.work + shared + Makefile)

**Files:**
- Create: `scenarios/README.md`
- Create: `scenarios/go.work`
- Create: `scenarios/Makefile`
- Create: `scenarios/shared/go.mod`
- Create: `scenarios/shared/logger/logger.go`
- Create: `scenarios/shared/config/config.go`
- Create: `scenarios/shared/metrics/metrics.go`
- Create: `scenarios/shared/logger/logger_test.go`

- [ ] **Step 3.1: scenarios/README.md**

내용: 시나리오 컨셉(MSA), 서비스 5종 역할 표, 로컬 실행 방법(`make up`), 빌드/푸시 방법(`make ecr-push`).

- [ ] **Step 3.2: shared 모듈 초기화**

```bash
cd /Users/finn/test/eks-study/scenarios/shared
go mod init github.com/finn/eks-study/shared
```

- [ ] **Step 3.3: shared/logger/logger.go 작성**

```go
package logger

import (
	"log/slog"
	"os"
)

func New(service string) *slog.Logger {
	h := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})
	return slog.New(h).With("service", service)
}
```

- [ ] **Step 3.4: shared/logger/logger_test.go (TDD)**

```go
package logger

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"testing"
)

func TestNewIncludesServiceField(t *testing.T) {
	var buf bytes.Buffer
	h := slog.NewJSONHandler(&buf, &slog.HandlerOptions{Level: slog.LevelInfo})
	l := slog.New(h).With("service", "order-service")
	l.Info("hello")

	var got map[string]any
	if err := json.Unmarshal(buf.Bytes(), &got); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if got["service"] != "order-service" {
		t.Errorf("expected service=order-service, got %v", got["service"])
	}
}
```

- [ ] **Step 3.5: 테스트 실행 (RED→GREEN 확인)**

```bash
cd /Users/finn/test/eks-study/scenarios/shared
go test ./logger/...
```

기대: PASS (구현이 이미 작동).

- [ ] **Step 3.6: shared/config/config.go**

```go
package config

import (
	"os"
	"strconv"
)

func GetString(key, def string) string {
	if v, ok := os.LookupEnv(key); ok {
		return v
	}
	return def
}

func GetInt(key string, def int) int {
	if v, ok := os.LookupEnv(key); ok {
		if i, err := strconv.Atoi(v); err == nil {
			return i
		}
	}
	return def
}
```

- [ ] **Step 3.7: shared/metrics/metrics.go**

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

`go get github.com/prometheus/client_golang` 도 step에 포함.

- [ ] **Step 3.8: scenarios/go.work**

```
go 1.22

use (
    ./shared
    ./order-service
    ./payment-service
    ./user-service
    ./notification-service
    ./frontend
)
```

- [ ] **Step 3.9: scenarios/Makefile**

```makefile
SERVICES := order-service payment-service user-service notification-service frontend
REGION ?= ap-northeast-2

.PHONY: test build docker up down ecr-push tidy

test:
	@for s in $(SERVICES) shared; do \
		echo "→ test $$s"; \
		(cd $$s && go test ./...) || exit 1; \
	done

build:
	@for s in $(SERVICES); do \
		echo "→ build $$s"; \
		(cd $$s && go build -o ../bin/$$s ./...) || exit 1; \
	done

docker:
	@for s in $(SERVICES); do \
		echo "→ docker build $$s"; \
		docker build -t eks-study/$$s:latest -f $$s/Dockerfile . || exit 1; \
	done

up:
	docker compose up -d

down:
	docker compose down -v

ecr-push:
	../00-prerequisites/scripts/ecr-push-all.sh

tidy:
	@for s in $(SERVICES) shared; do \
		(cd $$s && go mod tidy); \
	done
```

- [ ] **Step 3.10: 커밋**

```bash
cd /Users/finn/test/eks-study
ls scenarios/shared/  # 검증
```

기대: go.mod, logger/, config/, metrics/ 존재. (커밋은 git repo가 아니므로 스킵 — 후속 플랜에서 git init 결정)

---

## Task 4: order-service (Go + Gin REST API, TDD)

**Files:**
- Create: `scenarios/order-service/go.mod`
- Create: `scenarios/order-service/main.go`
- Create: `scenarios/order-service/handler/order.go`
- Create: `scenarios/order-service/handler/order_test.go`
- Create: `scenarios/order-service/Dockerfile`
- Create: `scenarios/order-service/README.md`

- [ ] **Step 4.1: 모듈 초기화**

```bash
cd /Users/finn/test/eks-study/scenarios/order-service
go mod init github.com/finn/eks-study/order-service
go get github.com/gin-gonic/gin
```

- [ ] **Step 4.2: 실패하는 테스트 작성**

`handler/order_test.go`:

```go
package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func setupRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	h := New()
	r.POST("/orders", h.Create)
	r.GET("/orders/:id", h.Get)
	return r
}

func TestCreateOrderReturns201(t *testing.T) {
	r := setupRouter()
	w := httptest.NewRecorder()
	body := `{"user_id":"u1","amount":1000}`
	req, _ := http.NewRequest("POST", "/orders", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")

	r.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d", w.Code)
	}
	var resp map[string]any
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp["id"] == nil || resp["id"] == "" {
		t.Errorf("expected non-empty id")
	}
}

func TestGetOrderReturns404WhenMissing(t *testing.T) {
	r := setupRouter()
	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/orders/nonexistent", nil)
	r.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}
```

- [ ] **Step 4.3: 테스트 실행 → 실패 확인**

```bash
go test ./handler/...
```

기대: FAIL ("handler.New" 미정의).

- [ ] **Step 4.4: 최소 구현**

`handler/order.go`:

```go
package handler

import (
	"net/http"
	"sync"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type Order struct {
	ID     string  `json:"id"`
	UserID string  `json:"user_id"`
	Amount float64 `json:"amount"`
}

type Handler struct {
	mu     sync.RWMutex
	orders map[string]Order
}

func New() *Handler {
	return &Handler{orders: make(map[string]Order)}
}

func (h *Handler) Create(c *gin.Context) {
	var o Order
	if err := c.ShouldBindJSON(&o); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	o.ID = uuid.NewString()
	h.mu.Lock()
	h.orders[o.ID] = o
	h.mu.Unlock()
	c.JSON(http.StatusCreated, o)
}

func (h *Handler) Get(c *gin.Context) {
	h.mu.RLock()
	o, ok := h.orders[c.Param("id")]
	h.mu.RUnlock()
	if !ok {
		c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}
	c.JSON(http.StatusOK, o)
}
```

`go get github.com/google/uuid` 도 포함.

- [ ] **Step 4.5: 테스트 통과 확인**

```bash
go test ./handler/... -v
```

기대: PASS (2 tests).

- [ ] **Step 4.6: main.go**

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

- [ ] **Step 4.7: Dockerfile (멀티스테이지 + distroless)**

```dockerfile
# syntax=docker/dockerfile:1.6
FROM golang:1.22-alpine AS builder
WORKDIR /workspace
COPY go.work ./
COPY shared/ shared/
COPY order-service/ order-service/
RUN cd order-service && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/order-service .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/order-service /order-service
EXPOSE 8080 9090
USER nonroot:nonroot
ENTRYPOINT ["/order-service"]
```

- [ ] **Step 4.8: README.md**

내용: 서비스 역할(주문 CRUD), 엔드포인트 표(POST /orders, GET /orders/:id, GET /healthz, GET :9090/metrics), 환경변수(PORT), 로컬 실행 명령(`go run .`), 테스트 명령.

- [ ] **Step 4.9: 빌드 & 실행 검증**

```bash
cd /Users/finn/test/eks-study/scenarios/order-service
go build -o /tmp/order-service . && echo OK
docker build -t eks-study/order-service:latest -f Dockerfile .. && echo OK
```

기대: 둘 다 성공.

---

## Task 5: payment-service (Go + AWS SQS consumer, TDD)

**Files:**
- Create: `scenarios/payment-service/{go.mod, main.go, Dockerfile, README.md}`
- Create: `scenarios/payment-service/consumer/sqs.go`
- Create: `scenarios/payment-service/consumer/sqs_test.go`

- [ ] **Step 5.1: 모듈 초기화**

```bash
cd /Users/finn/test/eks-study/scenarios/payment-service
go mod init github.com/finn/eks-study/payment-service
go get github.com/aws/aws-sdk-go-v2/service/sqs
```

- [ ] **Step 5.2: 실패하는 테스트 작성**

`consumer/sqs_test.go`:

```go
package consumer

import (
	"context"
	"errors"
	"testing"

	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/sqs/types"
)

type fakeClient struct {
	messages   []types.Message
	deletedIDs []string
	receiveErr error
}

func (f *fakeClient) ReceiveMessage(_ context.Context, _ *sqs.ReceiveMessageInput, _ ...func(*sqs.Options)) (*sqs.ReceiveMessageOutput, error) {
	if f.receiveErr != nil {
		return nil, f.receiveErr
	}
	out := &sqs.ReceiveMessageOutput{Messages: f.messages}
	f.messages = nil
	return out, nil
}

func (f *fakeClient) DeleteMessage(_ context.Context, in *sqs.DeleteMessageInput, _ ...func(*sqs.Options)) (*sqs.DeleteMessageOutput, error) {
	f.deletedIDs = append(f.deletedIDs, *in.ReceiptHandle)
	return &sqs.DeleteMessageOutput{}, nil
}

func TestConsumerProcessesAndDeletesMessages(t *testing.T) {
	body := `{"order_id":"o1","amount":100}`
	rh := "rh-1"
	client := &fakeClient{messages: []types.Message{{Body: &body, ReceiptHandle: &rh}}}

	c := New(client, "https://example/q")
	processed := 0
	c.Handler = func(ctx context.Context, payload []byte) error {
		processed++
		return nil
	}

	if err := c.PollOnce(context.Background()); err != nil {
		t.Fatal(err)
	}
	if processed != 1 {
		t.Errorf("expected 1 processed, got %d", processed)
	}
	if len(client.deletedIDs) != 1 {
		t.Errorf("expected 1 deletion, got %d", len(client.deletedIDs))
	}
}

func TestConsumerSurfacesReceiveError(t *testing.T) {
	client := &fakeClient{receiveErr: errors.New("boom")}
	c := New(client, "q")
	c.Handler = func(_ context.Context, _ []byte) error { return nil }
	if err := c.PollOnce(context.Background()); err == nil {
		t.Fatal("expected error, got nil")
	}
}
```

- [ ] **Step 5.3: 테스트 실행 → 실패 확인**

```bash
go test ./consumer/...
```

기대: FAIL.

- [ ] **Step 5.4: 최소 구현**

`consumer/sqs.go`:

```go
package consumer

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

type Client interface {
	ReceiveMessage(ctx context.Context, in *sqs.ReceiveMessageInput, opts ...func(*sqs.Options)) (*sqs.ReceiveMessageOutput, error)
	DeleteMessage(ctx context.Context, in *sqs.DeleteMessageInput, opts ...func(*sqs.Options)) (*sqs.DeleteMessageOutput, error)
}

type Consumer struct {
	client   Client
	queueURL string
	Handler  func(ctx context.Context, payload []byte) error
}

func New(client Client, queueURL string) *Consumer {
	return &Consumer{client: client, queueURL: queueURL}
}

func (c *Consumer) PollOnce(ctx context.Context) error {
	out, err := c.client.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
		QueueUrl:            aws.String(c.queueURL),
		MaxNumberOfMessages: 10,
		WaitTimeSeconds:     5,
	})
	if err != nil {
		return fmt.Errorf("receive: %w", err)
	}
	for _, m := range out.Messages {
		if err := c.Handler(ctx, []byte(*m.Body)); err != nil {
			continue
		}
		_, _ = c.client.DeleteMessage(ctx, &sqs.DeleteMessageInput{
			QueueUrl:      aws.String(c.queueURL),
			ReceiptHandle: m.ReceiptHandle,
		})
	}
	return nil
}

func (c *Consumer) Run(ctx context.Context) error {
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			if err := c.PollOnce(ctx); err != nil {
				return err
			}
		}
	}
}
```

- [ ] **Step 5.5: 테스트 통과 확인**

```bash
go test ./consumer/... -v
```

기대: PASS.

- [ ] **Step 5.6: main.go**

```go
package main

import (
	"context"
	"encoding/json"
	"net/http"
	"os/signal"
	"syscall"

	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/finn/eks-study/payment-service/consumer"
	cfg "github.com/finn/eks-study/shared/config"
	"github.com/finn/eks-study/shared/logger"
	"github.com/finn/eks-study/shared/metrics"
)

func main() {
	log := logger.New("payment-service")
	queueURL := cfg.GetString("SQS_QUEUE_URL", "")
	if queueURL == "" {
		log.Error("SQS_QUEUE_URL is required")
		return
	}

	awsCfg, err := config.LoadDefaultConfig(context.Background())
	if err != nil {
		log.Error("aws config", "err", err)
		return
	}
	c := consumer.New(sqs.NewFromConfig(awsCfg), queueURL)
	c.Handler = func(ctx context.Context, payload []byte) error {
		var msg map[string]any
		_ = json.Unmarshal(payload, &msg)
		log.Info("processed payment", "msg", msg)
		return nil
	}

	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", metrics.Handler())
		mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) })
		_ = http.ListenAndServe(":9090", mux)
	}()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	log.Info("starting consumer", "queue", queueURL)
	if err := c.Run(ctx); err != nil && err != context.Canceled {
		log.Error("run failed", "err", err)
	}
}
```

- [ ] **Step 5.7: Dockerfile**

Task 4의 Dockerfile과 동일한 패턴, `order-service` → `payment-service`로 치환.

```dockerfile
# syntax=docker/dockerfile:1.6
FROM golang:1.22-alpine AS builder
WORKDIR /workspace
COPY go.work ./
COPY shared/ shared/
COPY payment-service/ payment-service/
RUN cd payment-service && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/payment-service .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/payment-service /payment-service
EXPOSE 9090
USER nonroot:nonroot
ENTRYPOINT ["/payment-service"]
```

- [ ] **Step 5.8: README.md**

내용: 서비스 역할(SQS 메시지 → 결제 처리 시뮬레이션), 환경변수(SQS_QUEUE_URL, AWS_REGION), KEDA 스케일 트리거 (Part 3에서 사용 예정) 한 줄 안내.

- [ ] **Step 5.9: 빌드 검증**

```bash
cd /Users/finn/test/eks-study/scenarios/payment-service
go build -o /tmp/payment-service . && echo OK
```

---

## Task 6: user-service (Go + gRPC, TDD)

**Files:**
- Create: `scenarios/user-service/{go.mod, main.go, Dockerfile, README.md}`
- Create: `scenarios/user-service/proto/user.proto`
- Create: `scenarios/user-service/server/user.go`
- Create: `scenarios/user-service/server/user_test.go`

- [ ] **Step 6.1: 모듈 초기화 + gRPC 의존성**

```bash
cd /Users/finn/test/eks-study/scenarios/user-service
go mod init github.com/finn/eks-study/user-service
go get google.golang.org/grpc google.golang.org/protobuf
```

- [ ] **Step 6.2: proto/user.proto 작성**

```proto
syntax = "proto3";

package user.v1;
option go_package = "github.com/finn/eks-study/user-service/proto/userv1;userv1";

service UserService {
  rpc GetUser(GetUserRequest) returns (User);
  rpc CreateUser(CreateUserRequest) returns (User);
}

message User {
  string id = 1;
  string name = 2;
  string email = 3;
}
message GetUserRequest { string id = 1; }
message CreateUserRequest { string name = 1; string email = 2; }
```

- [ ] **Step 6.3: protoc 코드 생성**

```bash
brew install protobuf protoc-gen-go protoc-gen-go-grpc 2>/dev/null || true
mkdir -p proto/userv1
protoc --go_out=. --go_opt=paths=source_relative \
       --go-grpc_out=. --go-grpc_opt=paths=source_relative \
       proto/user.proto
mv proto/user.pb.go proto/userv1/
mv proto/user_grpc.pb.go proto/userv1/
```

(만약 protoc 설치 어려우면 미리 생성된 파일을 이 step에 포함하도록 대체 — 학습자 상황에 따라 안내)

- [ ] **Step 6.4: 실패하는 테스트 작성**

`server/user_test.go`:

```go
package server

import (
	"context"
	"testing"

	pb "github.com/finn/eks-study/user-service/proto/userv1"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func TestCreateAndGetUser(t *testing.T) {
	s := New()
	created, err := s.CreateUser(context.Background(), &pb.CreateUserRequest{Name: "finn", Email: "f@x.io"})
	if err != nil {
		t.Fatal(err)
	}
	if created.Id == "" {
		t.Fatal("expected non-empty id")
	}
	got, err := s.GetUser(context.Background(), &pb.GetUserRequest{Id: created.Id})
	if err != nil {
		t.Fatal(err)
	}
	if got.Name != "finn" {
		t.Errorf("expected finn, got %s", got.Name)
	}
}

func TestGetUserNotFoundReturnsNotFound(t *testing.T) {
	s := New()
	_, err := s.GetUser(context.Background(), &pb.GetUserRequest{Id: "missing"})
	if err == nil {
		t.Fatal("expected error")
	}
	if status.Code(err) != codes.NotFound {
		t.Errorf("expected NotFound, got %v", status.Code(err))
	}
}
```

- [ ] **Step 6.5: 테스트 실행 → 실패 확인**

```bash
go test ./server/...
```

기대: FAIL.

- [ ] **Step 6.6: 최소 구현**

`server/user.go`:

```go
package server

import (
	"context"
	"sync"

	pb "github.com/finn/eks-study/user-service/proto/userv1"
	"github.com/google/uuid"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type Server struct {
	pb.UnimplementedUserServiceServer
	mu    sync.RWMutex
	users map[string]*pb.User
}

func New() *Server { return &Server{users: make(map[string]*pb.User)} }

func (s *Server) CreateUser(_ context.Context, req *pb.CreateUserRequest) (*pb.User, error) {
	u := &pb.User{Id: uuid.NewString(), Name: req.Name, Email: req.Email}
	s.mu.Lock()
	s.users[u.Id] = u
	s.mu.Unlock()
	return u, nil
}

func (s *Server) GetUser(_ context.Context, req *pb.GetUserRequest) (*pb.User, error) {
	s.mu.RLock()
	u, ok := s.users[req.Id]
	s.mu.RUnlock()
	if !ok {
		return nil, status.Error(codes.NotFound, "user not found")
	}
	return u, nil
}
```

`go get github.com/google/uuid`.

- [ ] **Step 6.7: 테스트 통과 확인**

```bash
go test ./server/... -v
```

기대: PASS.

- [ ] **Step 6.8: main.go**

```go
package main

import (
	"net"
	"net/http"

	pb "github.com/finn/eks-study/user-service/proto/userv1"
	"github.com/finn/eks-study/user-service/server"
	cfg "github.com/finn/eks-study/shared/config"
	"github.com/finn/eks-study/shared/logger"
	"github.com/finn/eks-study/shared/metrics"
	"google.golang.org/grpc"
)

func main() {
	log := logger.New("user-service")
	port := cfg.GetString("GRPC_PORT", "50051")

	lis, err := net.Listen("tcp", ":"+port)
	if err != nil {
		log.Error("listen", "err", err)
		return
	}
	s := grpc.NewServer()
	pb.RegisterUserServiceServer(s, server.New())

	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", metrics.Handler())
		mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) })
		_ = http.ListenAndServe(":9090", mux)
	}()

	log.Info("gRPC starting", "port", port)
	if err := s.Serve(lis); err != nil {
		log.Error("serve", "err", err)
	}
}
```

- [ ] **Step 6.9: Dockerfile (Task 4 패턴 동일)**

```dockerfile
# syntax=docker/dockerfile:1.6
FROM golang:1.22-alpine AS builder
WORKDIR /workspace
COPY go.work ./
COPY shared/ shared/
COPY user-service/ user-service/
RUN cd user-service && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/user-service .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/user-service /user-service
EXPOSE 50051 9090
USER nonroot:nonroot
ENTRYPOINT ["/user-service"]
```

- [ ] **Step 6.10: README.md**

내용: 서비스 역할(gRPC 사용자 CRUD), proto 위치, 호출 예시(`grpcurl -plaintext localhost:50051 user.v1.UserService/GetUser`).

---

## Task 7: notification-service (Go + Kafka consumer, TDD)

**Files:**
- Create: `scenarios/notification-service/{go.mod, main.go, Dockerfile, README.md}`
- Create: `scenarios/notification-service/consumer/kafka.go`
- Create: `scenarios/notification-service/consumer/kafka_test.go`

- [ ] **Step 7.1: 모듈 초기화**

```bash
cd /Users/finn/test/eks-study/scenarios/notification-service
go mod init github.com/finn/eks-study/notification-service
go get github.com/segmentio/kafka-go
```

- [ ] **Step 7.2: 실패하는 테스트 작성**

`consumer/kafka_test.go`:

```go
package consumer

import (
	"context"
	"errors"
	"io"
	"testing"

	"github.com/segmentio/kafka-go"
)

type fakeReader struct {
	msgs []kafka.Message
	idx  int
}

func (f *fakeReader) FetchMessage(_ context.Context) (kafka.Message, error) {
	if f.idx >= len(f.msgs) {
		return kafka.Message{}, io.EOF
	}
	m := f.msgs[f.idx]
	f.idx++
	return m, nil
}
func (f *fakeReader) CommitMessages(_ context.Context, _ ...kafka.Message) error { return nil }
func (f *fakeReader) Close() error                                                 { return nil }

func TestProcessHandlesAllMessagesUntilEOF(t *testing.T) {
	r := &fakeReader{msgs: []kafka.Message{
		{Value: []byte(`{"to":"u1","msg":"hi"}`)},
		{Value: []byte(`{"to":"u2","msg":"yo"}`)},
	}}
	c := New(r)
	count := 0
	c.Handler = func(_ context.Context, _ []byte) error { count++; return nil }

	err := c.Run(context.Background())
	if !errors.Is(err, io.EOF) {
		t.Fatalf("expected EOF, got %v", err)
	}
	if count != 2 {
		t.Errorf("expected 2 processed, got %d", count)
	}
}
```

- [ ] **Step 7.3: 테스트 실행 → 실패 확인**

```bash
go test ./consumer/...
```

기대: FAIL.

- [ ] **Step 7.4: 최소 구현**

`consumer/kafka.go`:

```go
package consumer

import (
	"context"

	"github.com/segmentio/kafka-go"
)

type Reader interface {
	FetchMessage(ctx context.Context) (kafka.Message, error)
	CommitMessages(ctx context.Context, msgs ...kafka.Message) error
	Close() error
}

type Consumer struct {
	r       Reader
	Handler func(ctx context.Context, payload []byte) error
}

func New(r Reader) *Consumer { return &Consumer{r: r} }

func (c *Consumer) Run(ctx context.Context) error {
	for {
		m, err := c.r.FetchMessage(ctx)
		if err != nil {
			return err
		}
		if err := c.Handler(ctx, m.Value); err != nil {
			continue
		}
		_ = c.r.CommitMessages(ctx, m)
	}
}
```

- [ ] **Step 7.5: 테스트 통과 확인**

```bash
go test ./consumer/... -v
```

기대: PASS.

- [ ] **Step 7.6: main.go**

```go
package main

import (
	"context"
	"net/http"
	"os/signal"
	"strings"
	"syscall"

	"github.com/finn/eks-study/notification-service/consumer"
	cfg "github.com/finn/eks-study/shared/config"
	"github.com/finn/eks-study/shared/logger"
	"github.com/finn/eks-study/shared/metrics"
	"github.com/segmentio/kafka-go"
)

func main() {
	log := logger.New("notification-service")
	brokers := strings.Split(cfg.GetString("KAFKA_BROKERS", "localhost:9092"), ",")
	topic := cfg.GetString("KAFKA_TOPIC", "notifications")
	group := cfg.GetString("KAFKA_GROUP", "notification-service")

	r := kafka.NewReader(kafka.ReaderConfig{
		Brokers: brokers, Topic: topic, GroupID: group,
	})
	defer r.Close()

	c := consumer.New(r)
	c.Handler = func(_ context.Context, payload []byte) error {
		log.Info("notification", "payload", string(payload))
		return nil
	}

	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", metrics.Handler())
		mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) })
		_ = http.ListenAndServe(":9090", mux)
	}()

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	log.Info("kafka consumer starting", "topic", topic, "group", group)
	if err := c.Run(ctx); err != nil && err != context.Canceled {
		log.Error("consumer", "err", err)
	}
}
```

- [ ] **Step 7.7: Dockerfile**

```dockerfile
# syntax=docker/dockerfile:1.6
FROM golang:1.22-alpine AS builder
WORKDIR /workspace
COPY go.work ./
COPY shared/ shared/
COPY notification-service/ notification-service/
RUN cd notification-service && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/notification-service .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/notification-service /notification-service
EXPOSE 9090
USER nonroot:nonroot
ENTRYPOINT ["/notification-service"]
```

- [ ] **Step 7.8: README.md**

내용: 서비스 역할(Kafka topic 컨슘 → 알림 발송 시뮬레이션), 환경변수(KAFKA_BROKERS, KAFKA_TOPIC, KAFKA_GROUP), Part 3 KEDA Kafka 트리거에서 사용 예고.

---

## Task 8: frontend (Go + html/template SSR, TDD)

**Files:**
- Create: `scenarios/frontend/{go.mod, main.go, Dockerfile, README.md}`
- Create: `scenarios/frontend/handler/page.go`
- Create: `scenarios/frontend/handler/page_test.go`
- Create: `scenarios/frontend/templates/index.html`

- [ ] **Step 8.1: 모듈 초기화**

```bash
cd /Users/finn/test/eks-study/scenarios/frontend
go mod init github.com/finn/eks-study/frontend
```

- [ ] **Step 8.2: 실패하는 테스트 작성**

`handler/page_test.go`:

```go
package handler

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestIndexRendersTitle(t *testing.T) {
	h, err := New("../templates/*.html")
	if err != nil {
		t.Fatal(err)
	}
	w := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/", nil)
	h.Index(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	if !strings.Contains(w.Body.String(), "EKS Study Demo") {
		t.Errorf("expected title in body")
	}
}
```

- [ ] **Step 8.3: 테스트 실행 → 실패 확인**

```bash
go test ./handler/...
```

기대: FAIL.

- [ ] **Step 8.4: 템플릿 작성**

`templates/index.html`:

```html
<!doctype html>
<html lang="ko">
<head><meta charset="utf-8"><title>{{.Title}}</title></head>
<body>
  <h1>{{.Title}}</h1>
  <p>주문/결제/유저/알림 마이크로서비스 데모</p>
  <ul>
    <li>order-service: REST API</li>
    <li>payment-service: SQS Worker</li>
    <li>user-service: gRPC</li>
    <li>notification-service: Kafka Worker</li>
  </ul>
</body>
</html>
```

- [ ] **Step 8.5: 최소 구현**

`handler/page.go`:

```go
package handler

import (
	"html/template"
	"net/http"
)

type Handler struct{ tmpl *template.Template }

func New(glob string) (*Handler, error) {
	t, err := template.ParseGlob(glob)
	if err != nil {
		return nil, err
	}
	return &Handler{tmpl: t}, nil
}

func (h *Handler) Index(w http.ResponseWriter, _ *http.Request) {
	_ = h.tmpl.ExecuteTemplate(w, "index.html", map[string]string{"Title": "EKS Study Demo"})
}
```

- [ ] **Step 8.6: 테스트 통과 확인**

```bash
go test ./handler/... -v
```

기대: PASS.

- [ ] **Step 8.7: main.go**

```go
package main

import (
	"net/http"

	"github.com/finn/eks-study/frontend/handler"
	cfg "github.com/finn/eks-study/shared/config"
	"github.com/finn/eks-study/shared/logger"
	"github.com/finn/eks-study/shared/metrics"
)

func main() {
	log := logger.New("frontend")
	port := cfg.GetString("PORT", "8080")

	h, err := handler.New("templates/*.html")
	if err != nil {
		log.Error("template parse", "err", err)
		return
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/", h.Index)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(200) })
	mux.Handle("/metrics", metrics.Handler())

	log.Info("frontend starting", "port", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Error("listen", "err", err)
	}
}
```

- [ ] **Step 8.8: Dockerfile (templates 포함)**

```dockerfile
# syntax=docker/dockerfile:1.6
FROM golang:1.22-alpine AS builder
WORKDIR /workspace
COPY go.work ./
COPY shared/ shared/
COPY frontend/ frontend/
RUN cd frontend && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/frontend .

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=builder /out/frontend /app/frontend
COPY --from=builder /workspace/frontend/templates/ /app/templates/
EXPOSE 8080
USER nonroot:nonroot
ENTRYPOINT ["/app/frontend"]
```

- [ ] **Step 8.9: README.md**

내용: 정적 SSR 페이지, 로컬 실행 시 `http://localhost:8080` 접속.

---

## Task 9: docker-compose.yml (로컬 통합 검증)

**Files:**
- Create: `scenarios/docker-compose.yml`

- [ ] **Step 9.1: docker-compose.yml 작성**

```yaml
version: "3.9"
services:
  localstack:
    image: localstack/localstack:3
    environment: [SERVICES=sqs]
    ports: ["4566:4566"]

  kafka:
    image: bitnami/kafka:3.7
    environment:
      - KAFKA_CFG_PROCESS_ROLES=controller,broker
      - KAFKA_CFG_NODE_ID=1
      - KAFKA_CFG_LISTENERS=PLAINTEXT://:9092,CONTROLLER://:9093
      - KAFKA_CFG_ADVERTISED_LISTENERS=PLAINTEXT://kafka:9092
      - KAFKA_CFG_CONTROLLER_QUORUM_VOTERS=1@kafka:9093
      - KAFKA_CFG_CONTROLLER_LISTENER_NAMES=CONTROLLER
      - KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT
    ports: ["9092:9092"]

  order-service:
    build: { context: ., dockerfile: order-service/Dockerfile }
    ports: ["8080:8080", "9090:9090"]

  payment-service:
    build: { context: ., dockerfile: payment-service/Dockerfile }
    environment:
      - AWS_REGION=us-east-1
      - AWS_ACCESS_KEY_ID=test
      - AWS_SECRET_ACCESS_KEY=test
      - SQS_QUEUE_URL=http://localstack:4566/000000000000/payments
    depends_on: [localstack]

  user-service:
    build: { context: ., dockerfile: user-service/Dockerfile }
    ports: ["50051:50051"]

  notification-service:
    build: { context: ., dockerfile: notification-service/Dockerfile }
    environment:
      - KAFKA_BROKERS=kafka:9092
      - KAFKA_TOPIC=notifications
    depends_on: [kafka]

  frontend:
    build: { context: ., dockerfile: frontend/Dockerfile }
    ports: ["8081:8080"]
```

- [ ] **Step 9.2: 통합 실행 검증**

```bash
cd /Users/finn/test/eks-study/scenarios
docker compose build
docker compose up -d
sleep 10
curl -s http://localhost:8081/ | grep "EKS Study Demo"
curl -s -X POST http://localhost:8080/orders -H 'Content-Type: application/json' -d '{"user_id":"u1","amount":100}'
docker compose down -v
```

기대: 모든 빌드 성공, frontend 응답에 "EKS Study Demo" 포함, order POST 응답 201 + JSON `id` 필드.

(만약 docker daemon이 안 떠 있으면 실행 후 재시도 안내)

---

## Task 10: reference/ 치트시트

**Files:**
- Create: `reference/cheatsheet-kubectl.md`
- Create: `reference/cheatsheet-eksctl.md`
- Create: `reference/cheatsheet-helm.md`
- Create: `reference/cheatsheet-aws.md`
- Create: `reference/cost-guardrails.md`
- Create: `reference/links.md`

- [ ] **Step 10.1: cheatsheet-kubectl.md**

내용: 자주 쓰는 명령 (get/describe/logs/exec/apply/delete/rollout/port-forward/top/explain), 컨텍스트/네임스페이스 관리, JSON path 출력 예시. 약 50~80줄.

- [ ] **Step 10.2: cheatsheet-eksctl.md**

내용: 클러스터 생성/삭제, nodegroup 추가/스케일/삭제, IAM addon, addon 설치 (vpc-cni/coredns/kube-proxy/aws-ebs-csi-driver), update-kubeconfig.

- [ ] **Step 10.3: cheatsheet-helm.md**

내용: repo add/update, install/upgrade/uninstall, list/status/values, --dry-run, 차트 만들기 기본.

- [ ] **Step 10.4: cheatsheet-aws.md**

내용: aws configure, sts get-caller-identity, ecr 로그인/생성, eks list/describe, ec2 인스턴스 조회, cloudwatch logs tail, sqs/kinesis 흔한 명령.

- [ ] **Step 10.5: cost-guardrails.md**

내용: 핵심 원칙 5개(Spot 우선, 학습 후 cleanup, NLB→ClusterIP 우선, NAT Gateway 비용 인식, EBS gp3 사용), 잔존 리소스 점검 명령 모음, AWS Budgets 설정 절차.

- [ ] **Step 10.6: links.md**

내용 (외부 링크 모음):
- Kubernetes 공식: https://kubernetes.io/docs/
- EKS Best Practices: https://aws.github.io/aws-eks-best-practices/
- Karpenter: https://karpenter.sh/docs/
- KEDA: https://keda.sh/docs/
- AWS LB Controller: https://kubernetes-sigs.github.io/aws-load-balancer-controller/
- EBS CSI: https://github.com/kubernetes-sigs/aws-ebs-csi-driver
- 한국어 블로그: AWS Korea blog, 카카오/우아한기술블로그 EKS 글 모음

- [ ] **Step 10.7: 검증**

```bash
ls /Users/finn/test/eks-study/reference/
wc -l /Users/finn/test/eks-study/reference/*.md
```

기대: 6개 파일, 각 30줄 이상.

---

## 최종 검증

- [ ] **Step F.1: 디렉토리 구조 확인**

```bash
cd /Users/finn/test/eks-study
find . -maxdepth 3 -type d | sort
```

기대: spec §5에 정의된 모든 폴더 존재.

- [ ] **Step F.2: 시나리오 앱 전체 테스트**

```bash
cd /Users/finn/test/eks-study/scenarios
make test
```

기대: 모든 서비스 + shared 테스트 PASS.

- [ ] **Step F.3: 시나리오 앱 전체 도커 빌드**

```bash
cd /Users/finn/test/eks-study/scenarios
make docker
```

기대: 5개 이미지 빌드 성공.

- [ ] **Step F.4: docker-compose 통합 실행 (Task 9 재실행)**

위 Task 9 Step 9.2 그대로 실행, 동일 기대.

- [ ] **Step F.5: README 진도 체크리스트 확인**

`/Users/finn/test/eks-study/README.md`의 진도 체크리스트가 18개 모듈 전부 포함하는지 시각 확인.

---

## P0 완료 후 다음 단계

P0가 끝나면 다음 플랜은 P1 (Part 1: Kubernetes Basics) 작성. 이때 시나리오 앱 중 `order-service`만 우선 사용해 K8s 기본 개념(Pod/Deployment/Service/Ingress 등)을 학습.
