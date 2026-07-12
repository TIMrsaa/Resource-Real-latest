# frontend

Go `html/template` 기반 SSR (Server-Side Rendering) 프론트엔드.
시나리오 앱 데모 랜딩 페이지.

---

## SSR vs SPA (왜 SSR?)

| 항목 | SSR (이 서비스) | SPA (React/Next 등) |
|------|----------------|---------------------|
| 렌더링 | 서버에서 HTML 생성 | 브라우저에서 JS로 렌더 |
| 첫 응답 | 완성된 HTML | 빈 HTML + JS 번들 |
| SEO | ✅ 우수 | ⚠ 추가 작업 필요 |
| 학습 단순성 | ✅ 백엔드만 알아도 됨 | 프론트 빌드 체인 필요 |

→ 본 커리큘럼은 K8s/EKS 학습이 목표라 프론트엔드 복잡성 최소화.
   `html/template` 으로 100줄도 안 되게.

---

## 코드 한눈에 보기

```
main.go
  ├─ handler.New("templates/*.html")    # 템플릿 한번에 파싱 (메모리에 캐싱)
  ├─ mux.HandleFunc("/", h.Index)       # 루트 = 인덱스
  ├─ mux.HandleFunc("/healthz", ok)
  └─ mux.Handle("/metrics", metrics.Handler())

handler/page.go
  └─ template.Execute(w, data)          # data 를 HTML에 주입해 렌더

templates/index.html
  └─ {{ .Title }} 같은 Go 템플릿 문법
```

**왜 표준 net/http만 쓰고 Gin 안 씀?**
- order-service는 Gin (라우트가 많고 미들웨어 필요)
- frontend는 단일 페이지 (오버스펙 회피)
→ 같은 커리큘럼 안에서 두 가지 패턴 모두 보여줌

---

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `PORT` | `8080` | HTTP 리스너 포트 |

---

## 로컬 실행

```bash
go run .
# 출력: frontend starting port=8080

# 브라우저에서 http://localhost:8080 접속
```

---

## 테스트

```bash
go test ./...
```

`handler/page_test.go` = httptest.NewRecorder로 HTML 응답 검증.

---

## 도커 빌드 (scenarios/ 루트에서)

```bash
docker build -t eks-study/frontend:latest -f frontend/Dockerfile ..
```

---

## EKS 배포 시 노출 패턴 (Part-2-09)

frontend는 **외부 노출이 필요한 유일한 서비스**라 Ingress(ALB) 사용:

```yaml
# Service: ClusterIP (Ingress가 가리킴)
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  type: ClusterIP
  selector: {app: frontend}
  ports: [{port: 80, targetPort: 8080}]
---
# Ingress: ALB 자동 생성
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend
                port: {number: 80}
```

→ ALB DNS로 인터넷에서 접근 가능 (~$0.022/시 + LCU 과금).

**도메인 연결**:
실무에서는 Route53에 ALB DNS 의 alias 레코드 만들고 `app.example.com` 으로 노출.
External DNS Operator를 쓰면 Ingress의 host 어노테이션으로 자동화.
