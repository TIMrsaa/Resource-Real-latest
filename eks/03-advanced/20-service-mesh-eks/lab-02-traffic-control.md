# Lab 02 — 트래픽 문법: 카나리아, 고장 주입, 서킷브레이커

VirtualService/DestinationRule 두 장으로 동서 트래픽을 조종합니다 — 그리고 매 실험을 13의 도구로 **측정해서** 확인합니다.

전제: lab-01의 meshlab (STRICT mTLS, client/web 2/2).

## Step 1. 버전 두 개 — 카나리아의 재료

```bash
# v1/v2 — 같은 앱, 다른 메시지 (누가 응답했는지 표식)
for v in v1 v2; do
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: web-$v, namespace: meshlab }
spec:
  replicas: 1
  selector: { matchLabels: { app: web, version: $v } }
  template:
    metadata: { labels: { app: web, version: $v } }
    spec:
      containers:
      - name: podinfo
        image: ghcr.io/stefanprodan/podinfo:6.7.1
        env: [{ name: PODINFO_UI_MESSAGE, value: "$v" }]
        ports: [{ containerPort: 9898 }]
EOF
done
kubectl delete deployment web -n meshlab    # lab-01의 단일판 제거 (Service는 app=web으로 둘 다 선택)
kubectl rollout status deploy/web-v1 -n meshlab && kubectl rollout status deploy/web-v2 -n meshlab
```

## Step 2. 90/10 카나리아 — replicas와 무관한 분할

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: { name: web, namespace: meshlab }
spec:
  host: web
  subsets:
  - { name: v1, labels: { version: v1 } }
  - { name: v2, labels: { version: v2 } }
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata: { name: web, namespace: meshlab }
spec:
  hosts: [web]
  http:
  - route:
    - { destination: { host: web, subset: v1 }, weight: 90 }
    - { destination: { host: web, subset: v2 }, weight: 10 }
EOF

# 분포 실측 — 100번 호출해 표식을 셉니다
kubectl exec -n meshlab deploy/client -c podinfo -- sh -c \
  'for i in $(seq 1 100); do curl -s http://web:9898/ | grep -o "\"message\": \"v[12]\""; done | sort | uniq -c'
```

예상: `~90 "v1" / ~10 "v2"`. ✅ **Pod는 1:1인데 트래픽은 9:1** — replicas 비율로 어림하던 카나리아(그건 14 ALB 가중치도 마찬가지 한계)와 달리, 라우팅 규칙이 분할을 소유합니다. weight를 10→50→100으로 올리는 것이 곧 점진 배포.

## Step 3. fault 주입 — 코드 무수정 카오스

"하류가 느려지면 우리 타임아웃/재시도가 정말 동작하나"를 **프로덕션 코드 그대로** 리허설:

```bash
kubectl patch virtualservice web -n meshlab --type=merge -p '
spec:
  http:
  - fault:
      delay: { percentage: { value: 50 }, fixedDelay: 2s }
    route:
    - { destination: { host: web, subset: v1 }, weight: 90 }
    - { destination: { host: web, subset: v2 }, weight: 10 }'

# 측정 — p50은 멀쩡한데 p99가 2초로 (절반만 느리니까)
kubectl exec -n meshlab deploy/client -c podinfo -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{time_total}\n" http://web:9898/; done | sort -n | awk "NR==10{print \"p50≈\"\$1} NR==19{print \"p95≈\"\$1}"'
```

예상: p50 ≈ 수 ms, p95 ≈ **2초** — 앱은 결백한데 분포의 꼬리가 생겼습니다(13의 언어로 정확히 읽힙니다). fault를 제거하고:

```bash
kubectl patch virtualservice web -n meshlab --type=json -p='[{"op":"remove","path":"/spec/http/0/fault"}]'
```

## Step 4. 서킷브레이커 — 아픈 인스턴스 퇴출

v2를 고장내고(에러 주입 모드), outlierDetection이 퇴출하는지 봅니다:

```bash
# v2가 절반 확률로 500을 뱉게
kubectl set env deploy/web-v2 -n meshlab PODINFO_RANDOM_ERROR=true 2>/dev/null || \
kubectl patch deploy web-v2 -n meshlab --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/command","value":["./podinfo","--port=9898","--random-error=true"]}]'
kubectl rollout status deploy/web-v2 -n meshlab

# 서킷 장착
kubectl patch destinationrule web -n meshlab --type=merge -p '
spec:
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 3
      interval: 10s
      baseEjectionTime: 60s
      maxEjectionPercent: 100'

# 부하를 흘리면: 처음엔 5xx 섞임 → v2 퇴출 후 성공률 회복
kubectl exec -n meshlab deploy/client -c podinfo -- sh -c \
  'ok=0; err=0; for i in $(seq 1 100); do c=$(curl -s -o /dev/null -w "%{http_code}" http://web:9898/); [ $c = 200 ] && ok=$((ok+1)) || err=$((err+1)); done; echo "200: $ok / 5xx: $err"'
```

예상: 오류가 **초반 몇 개에 그칩니다** — 연속 5xx를 본 Envoy가 v2 엔드포인트를 잠시 로드밸런싱에서 뺐습니다(ejection). 60초 후 슬쩍 복귀시켜 재평가하는 것까지가 서킷의 생애. ✅ 14의 LOR이 "느린 타깃 회피"였다면 이것은 "**아픈 타깃 격리**" — 그리고 retry를 쓸 거라면 이 서킷이 폭풍 방지 안전벨트입니다(theory §4).

## Step 5. 고급 트랙 졸업 워크시트 (산출물)

```markdown
# 동서 트래픽 제어 설계 — 우리 서비스 맵
- mTLS: ns __부터 STRICT (lab-01 runbook) / 예외 목록: __
- 카나리아 표준: weight 10→50→100, 게이트는 골든 메트릭(오류율·p99)
- 타임아웃/재시도 예산: 호출 체인별 (retry는 서킷과 반드시 세트)
- fault 주입 리허설: 분기 1회 — 대상: 최장 호출 체인
- 메시 비용 회계: sidecar 메모리 합계 __ / 그 값어치를 하는가(guide의 신호표) 재평가: 반기
```

## 정리

```bash
bash cleanup.sh
```
