# Lab 02 — 메모리 누수 사냥 (동선의 완성)

> 05의 질문 카탈로그에서 "메모리 누수 의심 → 확정·원인은 프로파일링(20)"으로 미뤄 둔 그 동선을 완성합니다 — 누수가 심어진 앱을 메트릭 추세로 의심하고, inuse 프로파일 diff로 범인 코드를 짚습니다.

## 0. 준비 (lab-01 이어서) — 누수가 심어진 앱

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata: { name: leaky-src, namespace: shop }
data:
  main.go: |
    package main
    import (
      "fmt"
      "net/http"
      "os"
      "github.com/grafana/pyroscope-go"
    )
    var cache = map[string][]byte{}          // ★ 무한 캐시 — 전형적 누수
    var counter int
    func leakyCache(key string) {
      cache[key] = make([]byte, 64*1024)     // 요청마다 64KB, 영원히 보유
    }
    func handler(w http.ResponseWriter, r *http.Request) {
      counter++
      leakyCache(fmt.Sprintf("req-%d", counter))   // 키가 매번 달라 캐시 히트 0
      w.Write([]byte("ok"))
    }
    func main() {
      pyroscope.Start(pyroscope.Config{
        ApplicationName: "orders",
        ServerAddress:   os.Getenv("PYROSCOPE_URL"),
        ProfileTypes: []pyroscope.ProfileType{
          pyroscope.ProfileCPU,
          pyroscope.ProfileInuseObjects, pyroscope.ProfileInuseSpace,   // ★ inuse!
          pyroscope.ProfileAllocObjects, pyroscope.ProfileAllocSpace,
        },
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
metadata: { name: orders, namespace: shop }
spec:
  replicas: 1
  selector: { matchLabels: { app: orders } }
  template:
    metadata: { labels: { app: orders } }
    spec:
      containers:
        - name: app
          image: golang:1.22
          workingDir: /src
          command: ["sh","-c","cp /cm/* . && go mod tidy -e && go run main.go"]
          env: [{ name: PYROSCOPE_URL, value: "http://pyroscope.profiling.svc:4040" }]
          resources: { limits: { memory: "512Mi" } }     # OOM의 무대
          volumeMounts: [{ name: src, mountPath: /cm }]
      volumes: [{ name: src, configMap: { name: leaky-src } }]
---
apiVersion: v1
kind: Service
metadata: { name: orders, namespace: shop }
spec: { selector: { app: orders }, ports: [{ port: 8080 }] }
EOF
kubectl -n shop rollout status deploy/orders --timeout=600s

kubectl -n shop run leak-load --image=curlimages/curl --restart=Never -- sh -c '
  while true; do curl -s http://orders:8080/ >/dev/null; sleep 0.05; done'
```

## 1. 동선 ① — 메트릭 추세로 의심 (05까지의 능력)

```bash
# 메모리 우상향 확인 (metrics-server 또는 kubectl top의 간이 관찰)
for i in 1 2 3; do kubectl top pod -n shop -l app=orders --no-headers 2>/dev/null; sleep 60; done
# orders-xxx  ...  120Mi → 180Mi → 240Mi   ← 단조 증가 (부하는 일정한데!)
```

**05 시점의 한계 재확인** — 여기까지의 결론은 "누수 같습니다, limits(512Mi)에 곧 닿아 OOMKilled 예정" — 처방은 재시작(임시)뿐. **누가** 잡고 있는지 모르면 코드 수정을 못 합니다.

## 2. 동선 ② — inuse 프로파일로 범인 지목

```bash
kubectl -n profiling port-forward svc/pyroscope 4040:4040 &
# UI: Application orders → profile type: inuse_space
```

```
플레임그래프:
  [handler ██████████████████████ ~97% of inuse]
    [leakyCache ██████████████████████]
      [make([]byte) — inuse_space가 시간과 함께 증가]
  → ★ 보유 메모리의 97%가 handler→leakyCache의 할당 — 범인 지목!

diff(30분 전 vs 지금): leakyCache만 빨갛게 자랍니다 — 다른 스택은 평평
  → "자라는 스택"이 누수의 서명 (일회성 큰 할당과 구분됨)

alloc vs inuse 확인 훈련:
  alloc_space에는 정상 요청 처리의 할당도 많습니다 (GC가 회수 — 누수 아님)
  inuse_space의 증가만이 누수 — ★ "누수는 inuse로" (theory 4절)
```

## 3. 동선 ③ — 코드 확정과 수정 검증 (개념)

```
지목된 스택 → 코드: leakyCache의 cache[key] = ... — 무한 맵 + 매번 새 키
수정: LRU·TTL 캐시로 교체 (또는 키 설계 수정)
검증: 배포 후 같은 동선 재실행 —
  메트릭: working_set이 평평해졌나
  프로파일: inuse에서 해당 스택이 더 안 자라나
→ "의심(메트릭) → 지목(프로파일) → 수정(코드) → 검증(둘 다)"의 원이 닫힘
```

## 4. 영토 지도 최종판 — advanced 트랙의 마무리

19 lab-02의 분담표에 프로파일링 열을 채워 완성하세요:

| 질문 | 메트릭 | 로그 | 트레이스 | eBPF | 프로파일 |
|------|--------|------|----------|------|----------|
| 무엇이 이상? | ★ | | | | |
| 어디가(서비스·구간)? | | | ★ | 통신은 | |
| 왜(사건·서술)? | | ★ | | | |
| 연결·정책 문제? | | | | ★ | |
| 어느 코드가(CPU·메모리)? | | | | | ★ |
| 누수의 범인? | 의심만 | | | | ★ inuse |

```
SIGNALS-MAP 최종 갱신:
  프로파일 줄 추가: Pyroscope(SDK) 또는 Parca(eBPF) — CPU·inuse, diff
  질문 카탈로그의 "메모리 누수" 항목 완성: 메트릭 추세→inuse diff→코드
갱신 로그: "20 수료 — advanced 트랙 완료. 다섯 신호의 영토 지도 완성"
```

## 5. 정리

```bash
kill %1 2>/dev/null || true
kind delete cluster --name profiling
```

## 정리

- 메트릭(의심)의 한계를 inuse 프로파일(지목)이 넘습니다 — 재시작 처방에서 코드 수정으로
- **누수는 inuse로** — alloc의 대부분은 GC가 회수하는 정상 churn
- diff에서 "자라는 스택"이 누수의 서명 — 일회성 할당과의 구분
- 원이 닫힙니다: 의심(메트릭)→지목(프로파일)→수정(코드)→검증(둘 다)
- **★ advanced 수료: 다섯 신호(메트릭·로그·트레이스·eBPF·프로파일)의 영토 지도 완성 — production(21~)은 이 위의 운영**
