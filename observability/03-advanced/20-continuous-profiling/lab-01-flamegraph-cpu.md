# Lab 01 — 지속 프로파일링 배포·플레임그래프·diff

> Pyroscope를 배포하고, CPU를 태우는 함수가 심어진 Go 앱을 프로파일링해 플레임그래프에서 범인을 짚습니다. 그리고 "새 버전 배포"로 회귀를 만들어 diff의 힘을 확인합니다.

## 0. 준비

```bash
kind create cluster --name profiling

helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null; helm repo update
helm install pyroscope grafana/pyroscope -n profiling --create-namespace
kubectl -n profiling rollout status statefulset/pyroscope --timeout=300s
```

## 1. 범인이 심어진 앱 — v1

```bash
kubectl create namespace shop
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata: { name: app-src, namespace: shop }
data:
  main.go: |
    package main
    import (
      "crypto/sha256"
      "net/http"
      "os"
      "github.com/grafana/pyroscope-go"
    )
    func wastefulHash(data []byte) []byte {     // ★ 범인: 불필요한 반복 해시
      h := data
      for i := 0; i < 2000; i++ {
        s := sha256.Sum256(h); h = s[:]
      }
      return h
    }
    func cheapWork(data []byte) []byte {
      s := sha256.Sum256(data); return s[:]
    }
    func handler(w http.ResponseWriter, r *http.Request) {
      _ = cheapWork([]byte("payload"))
      _ = wastefulHash([]byte("payload"))       // 매 요청마다!
      w.Write([]byte("ok"))
    }
    func main() {
      pyroscope.Start(pyroscope.Config{
        ApplicationName: "payment",
        ServerAddress:   os.Getenv("PYROSCOPE_URL"),
      })
      http.HandleFunc("/", handler)
      http.ListenAndServe(":8080", nil)
    }
  go.mod: |
    module app
    go 1.22
    require github.com/grafana/pyroscope-go v1.1.1
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: payment, namespace: shop }
spec:
  replicas: 1
  selector: { matchLabels: { app: payment } }
  template:
    metadata: { labels: { app: payment } }
    spec:
      containers:
        - name: app
          image: golang:1.22
          workingDir: /src
          command: ["sh","-c","cp /cm/* . && go mod tidy -e && go run main.go"]
          env:
            - { name: PYROSCOPE_URL, value: "http://pyroscope.profiling.svc:4040" }
          ports: [{ containerPort: 8080 }]
          volumeMounts: [{ name: src, mountPath: /cm }]
      volumes: [{ name: src, configMap: { name: app-src } }]
---
apiVersion: v1
kind: Service
metadata: { name: payment, namespace: shop }
spec: { selector: { app: payment }, ports: [{ port: 8080 }] }
EOF
kubectl -n shop rollout status deploy/payment --timeout=600s   # go mod 다운로드 시간

# 부하
kubectl -n shop run load --image=curlimages/curl --restart=Never -- sh -c '
  while true; do curl -s http://payment:8080/ >/dev/null; done'
sleep 120   # 프로파일 축적
```

(Go SDK 통합 방식을 썼습니다 — 런타임 pprof 기반의 정밀 프로파일. eBPF 전체 샘플링 방식(Parca)이면 SDK조차 불필요하다는 점을 병기해 둡니다: 19의 "계측 제로"가 프로파일에도.)

## 2. 플레임그래프에서 범인 짚기

```bash
kubectl -n profiling port-forward svc/pyroscope 4040:4040 &
# 브라우저: http://localhost:4040 → Application: payment → CPU 플레임그래프
```

```
읽기 (guide의 30초 법):
  main → http.HandlerFunc → handler 아래에서
  [wastefulHash ████████████████████ ~95%]   ← 압도적으로 넓은 탑!
  [cheapWork █ ~2%]
  → 범인: wastefulHash (그 아래 sha256 프레임들이 실제 소비처)

결론 문장 훈련: "CPU의 95%가 handler→wastefulHash→sha256 경로 —
  요청당 2000회 반복 해시가 원인. cheapWork는 무죄."
  → 메트릭("CPU 높음")·트레이스("handler 느림")가 못 하던
    함수 수준의 지목 — 마지막 1미터
```

## 3. 회귀 재현 — diff의 힘

"최적화 배포"(사실은 더 나쁜 버전)를 흉내 냅니다:

```bash
# v2: 반복을 2000→4000으로 (성능 회귀!)
kubectl -n shop get cm app-src -o yaml | sed 's/i < 2000/i < 4000/' | kubectl apply -f -
kubectl -n shop rollout restart deploy/payment
kubectl -n shop rollout status deploy/payment --timeout=600s
sleep 120   # v2 프로파일 축적
```

```
Pyroscope UI → Comparison(diff) 뷰:
  좌: v2 배포 전 시간 범위 / 우: 배포 후
  → wastefulHash가 빨갛게(증가) — "이번 배포에서 이 함수가 더 먹기 시작"
  → 배포 마커(09)와 결합하면: 에러율·지연 회귀의 "범인 코드"까지
    한 동선 (메트릭 이상→diff 프로파일→커밋 리뷰)
```

**지속의 보상** — "배포 전"의 프로파일이 있었기에 비교가 됐습니다. 문제 후에 도구를 붙였다면 기준선(before)이 없습니다 — 05의 "휘발된 신호는 없는 신호"가 프로파일에서도.

## 4. 정리

```bash
kill %1 2>/dev/null || true
kubectl -n shop delete pod load --force --grace-period=0 2>/dev/null || true
# 클러스터는 lab-02에서 계속
```

## 정리

- 지속 프로파일링 배포(Pyroscope) + Go SDK — eBPF 방식(Parca)이면 SDK도 불필요
- 플레임그래프: 넓은 탑을 따라가 leaf를 짚습니다 — "95%가 wastefulHash" 수준의 지목
- diff 뷰 = 배포 전후 비교 — 회귀의 범인 코드가 한 화면 (기준선이 있어야 = 지속의 이유)
- 동선 완결: 메트릭(무엇이)→트레이스(어디가)→프로파일(어느 코드가)
- **★ 조사의 마지막 1미터 — "함수 이름"까지 가야 코드 리뷰·수정으로 이어집니다**
