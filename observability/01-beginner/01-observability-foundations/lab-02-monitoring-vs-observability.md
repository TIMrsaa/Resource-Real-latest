# Lab 02 — 같은 장애, 두 방식의 조사

> 모니터링(정한 질문)과 관측 가능성(새 질문)의 차이를 말이 아니라 **몸으로** 겪습니다. 일부러 미묘한 장애(전면 다운이 아닌 "일부만 느림")를 만들고, "체크 목록"만으로 조사할 때와 "신호를 넘나들며" 조사할 때를 비교합니다.

## 0. 준비 (lab-01의 클러스터 이어서)

두 버전이 섞인 서비스를 만듭니다 — v2에만 느린 결함을 심습니다:

```bash
# v1: 정상 (즉시 응답)
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: api-v1 }
spec:
  replicas: 2
  selector: { matchLabels: { app: api, ver: v1 } }
  template:
    metadata: { labels: { app: api, ver: v1 } }
    spec:
      containers:
        - name: api
          image: hashicorp/http-echo
          args: ["-text=ok-v1", "-listen=:8080"]
          ports: [{ containerPort: 8080 }]
EOF

# v2: 결함 — 프록시로 1.5초 지연을 흉내 (nginx + lua 없이 간단히: sleep 사이드카 아님, 
#     httpbin의 /delay를 사용)
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: api-v2 }
spec:
  replicas: 1
  selector: { matchLabels: { app: api, ver: v2 } }
  template:
    metadata: { labels: { app: api, ver: v2 } }
    spec:
      containers:
        - name: api
          image: kennethreitz/httpbin
          ports: [{ containerPort: 80 }]
EOF

# 하나의 Service가 v1(빠름) 2개 + v2(느리게 호출할 것) 1개를 묶습니다
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Service
metadata: { name: api }
spec:
  selector: { app: api }        # ver 라벨 없이 → v1·v2 모두
  ports: [{ port: 80, targetPort: 8080 }]
EOF
# (httpbin은 80 포트라 targetPort가 어긋남 → v2로 간 요청은 실패/지연 — 의도된 미묘함)
kubectl wait deploy/api-v1 deploy/api-v2 --for=condition=Available --timeout=120s
```

## 1. 증상 만들기 — "가끔만 이상해요"

```bash
# 클라이언트가 반복 호출 — 2/3는 성공(v1), 1/3은 실패(v2, 포트 불일치)
kubectl run client --image=curlimages/curl --restart=Never -- \
  sh -c 'for i in $(seq 1 30); do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://api) ;
    echo "req $i -> $code";
  done'
sleep 40
kubectl logs client | sort | uniq -c | sort -rn
#  20 req ... -> 200      ← 2/3 성공
#  10 req ... -> 000      ← 1/3 타임아웃/거부!
```

사용자 신고: **"API가 가끔 안 돼요."** — 전면 장애가 아닙니다. 이제 조사합니다.

## 2. 방식 A — 모니터링의 눈 (정한 질문 체크리스트)

전통적 체크리스트만 사용해 봅니다:

```bash
# 체크 1: Pod 다 살아있나요?
kubectl get pods -l app=api
# api-v1-... Running, api-v1-... Running, api-v2-... Running  → 전부 정상!

# 체크 2: 재시작 있나요?
kubectl get pods -l app=api -o custom-columns=NAME:.metadata.name,RESTARTS:.status.containerStatuses[0].restartCount
# 전부 0  → 정상!

# 체크 3: 노드 리소스?
kubectl describe node | grep -A5 "Allocated resources"
# 여유  → 정상!

# 체크 4: 최근 이벤트에 에러?
kubectl get events --field-selector type=Warning | tail
# (특별한 것 없음)  → 정상!
```

**막다른 길** — 모든 체크가 "정상"인데 사용자는 실패를 겪습니다. 정한 질문들("Pod 살아있나요?")은 이 장애 모드("일부 엔드포인트만 연결 불가")를 물어보지 않기 때문입니다. 이것이 모니터링의 한계 — **미리 상상한 장애만 잡습니다.**

## 3. 방식 B — 관측의 눈 (신호를 넘나들며 새 질문)

```bash
# 질문 1: "실패가 정말 있나요? 얼마나요?" → (메트릭이 있다면 5xx율로 즉답이지만)
#   지금은 클라이언트 로그로 확인: 1/3 실패 (위에서 확인)

# 질문 2: "실패는 무작위인가, 패턴이 있나요?"
#   → 실패한 요청이 어느 백엔드로 갔는지가 관건
kubectl get endpointslices -l kubernetes.io/service-name=api -o wide
# 주소 3개: v1 Pod 2개(8080 OK) + v2 Pod 1개
# ★ 1/3 실패 = 백엔드 3개 중 1개 — 패턴 발견!

# 질문 3: "그 하나는 뭐가 다른가?"
kubectl get pods -l app=api -L ver
# NAME         VER
# api-v1-...   v1
# api-v1-...   v1
# api-v2-...   v2    ← 버전이 다릅니다!

# 질문 4: "v2로 간 요청은 왜 실패하나요?"
kubectl exec client -- true 2>/dev/null || kubectl run probe --image=curlimages/curl --restart=Never -- \
  sh -c 'V2IP=api-v2; curl -sv --max-time 2 http://'"$(kubectl get pod -l ver=v2 -o jsonpath='{.items[0].status.podIP}')"':8080/ 2>&1 | tail -3'
sleep 8; kubectl logs probe 2>/dev/null | tail -3
# Connection refused / timeout — v2는 8080을 안 듣습니다!

# 질문 5: "왜 8080을 안 듣지?" → 스펙 비교
kubectl get deploy api-v2 -o jsonpath='{.spec.template.spec.containers[0].ports}'
# [{"containerPort":80}]   ← v2는 80 포트인데 Service targetPort는 8080
# 원인: Service의 targetPort(8080)와 v2 컨테이너 포트(80)의 불일치
```

**대비** — 방식 B는 정한 체크가 아니라 **데이터가 이끄는 질문 연쇄**였습니다: 실패율(얼마나) → 패턴(1/3=백엔드 하나) → 차이(버전) → 직접 검증(포트) → 원인(스펙 불일치). 각 단계에서 "다음 질문"은 이전 답이 정했습니다 — 이것이 관측 가능성이 뒷받침하는 조사입니다.

## 4. 회고 — 도구가 있었다면

```
이번엔 kubectl 수작업으로 신호를 넘나들었습니다. 파이프라인이 있다면:

  메트릭(08): rate(http_requests_total{code!="200"}[5m]) → "33% 실패" 즉시 + 알림
  라벨 분해: sum by (pod) (...) → "api-v2 Pod만 실패" 즉시
  트레이스(11): 실패 요청의 span → "connection refused to :8080" 즉시
  이벤트/배포 이력: "v2가 언제 배포됐나" → 회귀 시점 특정

→ 같은 조사가 5분 → 30초로. Part 5의 나머지는 이 도구들을 실제로 세우는 일입니다.
```

## 5. 정리

```bash
kind delete cluster --name obs-tour
```

## 정리

- 모니터링(정한 체크)은 "Pod 살아있나"만 물었고 — 전부 정상이라 **막다른 길**
- 관측의 조사는 데이터가 이끄는 질문 연쇄: 얼마나→패턴→차이→검증→원인
- 미묘한 장애(일부만·특정 조합만)가 K8s의 일상 — 정한 질문으론 못 잡습니다
- 파이프라인(메트릭 라벨 분해·트레이스)이 있으면 같은 조사가 분 단위 → 초 단위
- **★ 관측 가능성 = 새 질문에 답할 수 있는 능력 — 이 능력을 만드는 것이 Part 5 전체의 목적**
