# Lab 02 — 구조화 로깅과 trace_id 상관: 조사 동선을 닫습니다

06 사고 사례가 실패한 지점 — 로그를 트레이스와 이을 수 없었던 것 — 을 고칩니다. 관측 심층 트랙(11~14)의 마지막 조각.

전제: lab-01의 클러스터(kind: logs).

## Step 1. 나쁜 로그 vs 좋은 로그 — 앱을 두 버전으로

```bash
kubectl create configmap apps --from-literal=bad.py='
import time, random, sys
while True:
    dur = random.randint(10, 700)
    if dur > 500:
        print(f"{time.strftime(\"%Y-%m-%d %H:%M:%S\")} ERROR payment failed for user {random.randint(1,9999)} after {dur}ms", flush=True)
    else:
        print(f"{time.strftime(\"%Y-%m-%d %H:%M:%S\")} INFO  payment ok in {dur}ms", flush=True)
    time.sleep(1)
' --from-literal=good.py='
import time, random, json, sys, os
# 실전에서는 OTel 로깅 통합이 trace_id/span_id를 자동 주입합니다 (12)
def log(level, msg, **kw):
    rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ"), "level": level, "msg": msg,
           "service.name": "payment", **kw}
    print(json.dumps(rec), flush=True)

while True:
    trace_id = "%032x" % random.getrandbits(128)
    span_id  = "%016x" % random.getrandbits(64)
    dur = random.randint(10, 700)
    if dur > 500:
        log("error", "payment failed", trace_id=trace_id, span_id=span_id,
            user_id=str(random.randint(1,9999)), duration_ms=dur,
            error_kind="gateway_timeout")
    else:
        log("info", "payment ok", trace_id=trace_id, span_id=span_id, duration_ms=dur)
    time.sleep(1)
' >/dev/null

for V in bad good; do
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata: { name: app-$V, labels: { app: app-$V } }
spec:
  containers:
    - name: app
      image: python:3.12-slim
      command: ["python","/src/$V.py"]
      volumeMounts: [{ name: src, mountPath: /src }]
  volumes: [{ name: src, configMap: { name: apps } }]
EOF
done
kubectl wait --for=condition=ready pod/app-bad pod/app-good --timeout=120s
sleep 15
```

## Step 2. 파서가 하는 일의 차이

```bash
# 정상 설정으로 되돌리고, JSON 파싱을 켭니다
cat > /tmp/fb-json.yaml <<'EOF'
config:
  service: |
    [SERVICE]
        Flush 1
        Log_Level info
        Parsers_File /fluent-bit/etc/parsers.conf
        HTTP_Server On
        HTTP_Listen 0.0.0.0
        HTTP_Port 2020
  inputs: |
    [INPUT]
        Name tail
        Path /var/log/containers/app-*.log
        multiline.parser cri
        Tag kube.*
        Mem_Buf_Limit 20MB
        storage.type memory
  filters: |
    [FILTER]
        Name kubernetes
        Match kube.*
        Merge_Log On                # ★ log 필드가 JSON이면 파싱해 최상위로 병합
        Merge_Log_Key app
        Keep_Log Off
  outputs: |
    [OUTPUT]
        Name stdout
        Match kube.*
        Format json_lines
EOF
helm upgrade fb fluent/fluent-bit -n logging -f /tmp/fb-json.yaml >/dev/null
kubectl -n logging rollout status ds/fb-fluent-bit --timeout=120s
sleep 20

echo "=== app-bad (평문) 의 레코드 ==="
kubectl -n logging logs ds/fb-fluent-bit --tail=200 | grep "app-bad" | tail -1 | python3 -m json.tool 2>/dev/null | head -12

echo ""
echo "=== app-good (구조화 JSON) 의 레코드 ==="
kubectl -n logging logs ds/fb-fluent-bit --tail=200 | grep "app-good" | tail -1 | python3 -m json.tool 2>/dev/null | head -18
```

예상: bad는 `log: "2026-... ERROR payment failed for user 4821 after 612ms"` **한 덩어리 문자열**. good은 `level`, `trace_id`, `user_id`, `duration_ms`, `error_kind`가 **각각의 필드**로. ✅ `Merge_Log On`이 JSON 로그를 파싱해 최상위로 올렸습니다.

## Step 3. 검색 가능성의 차이 — 조사 시나리오

```bash
cat <<'EOF'
[시나리오] "gateway timeout으로 실패한 결제 중 600ms 넘는 것"

평문 로그(bad):
  grep "payment failed" | grep -oP 'after \K\d+' | awk '$1>600'
  → 정규식 유지보수 지옥, 로그 형식이 바뀌면 깨짐, 백엔드 인덱싱 불가

구조화 로그(good):
  {level="error", error_kind="gateway_timeout"} | duration_ms > 600     (LogQL)
  error_kind:"gateway_timeout" AND duration_ms:>600                     (ES)
  → 필드 기반, 형식 변경에 강함, 백엔드가 인덱싱 가능

★ 그리고 결정적 차이:
  구조화 로그에는 trace_id가 있습니다 → 13의 조사 동선이 이어집니다
EOF
```

## Step 4. 상관 실증 — trace_id로 세 신호를 잇습니다

```bash
# good 앱의 에러 로그에서 trace_id 하나를 뽑습니다
TID=$(kubectl -n logging logs ds/fb-fluent-bit --tail=300 | grep "app-good" | \
  python3 -c "
import json,sys
for line in sys.stdin:
    try: d = json.loads(line)
    except: continue
    if d.get('level')=='error' and d.get('trace_id'):
        print(d['trace_id']); break
")
echo "에러 로그의 trace_id: $TID"

cat <<EOF

=== 조사 동선의 완성 (11~14 종합) ===
1. 알람      : SLO 위반 (Prometheus — 11)
                 sum(rate(payment_errors_total[5m])) / sum(rate(payment_total[5m])) > 0.01
2. 진입      : exemplar 또는 지연 롱테일 → trace_id 획득 (13)
3. 트레이스  : span 트리에서 병목·에러 구간 (Jaeger — 13)
4. 로그      : trace_id="$TID" 로 조회 (지금 이 lab)
                 {service_name="payment"} | json | trace_id="$TID"
5. 원인      : error_kind="gateway_timeout", duration_ms=612, user_id=...

★ 4번이 가능한 유일한 조건: 로그에 trace_id가 구조화 필드로 있을 것
   06 사고 사례는 정확히 이 한 필드가 없어서 조사가 끊겼습니다
EOF
```

## Step 5. 카디널리티 규칙의 반전 — 로그는 다릅니다

```bash
cat <<'EOF'
11에서: 메트릭 라벨에 user_id 금지 (시계열 폭발)
14에서: 로그 필드에 user_id 환영 ✅

왜 다른가:
  메트릭 = 라벨 조합마다 시계열 하나가 '상주' → 카디널리티가 메모리를 먹습니다
  로그   = 레코드 하나에 필드가 붙을 뿐 → 카디널리티는 인덱스 비용에만 영향

단, 로그에도 비용은 있습니다:
  - 저장하는 백엔드가 '모든 필드를 인덱싱'하면 ES 인덱스가 폭발(13의 태그 교훈과 동일)
  - Loki의 철학: 라벨(인덱싱)은 저카디널리티만, 본문은 검색 시 스캔
    → 라벨: service, namespace, level   /  본문 필드: trace_id, user_id, duration_ms
★ 06의 신호 분업이 여기서 완성: "개별 사건의 식별자"는 로그·트레이스의 영토입니다
EOF
```

## Step 6. 볼륨 절감 — 가장 싼 곳부터

```bash
cat <<'EOF'
# 절감 순서 (theory §6)
① 앱: 프로덕션 로그 레벨 info 이하 억제, 반복 로그 dedupe
② 에이전트: 노이즈 drop (헬스체크 200 등)
   [FILTER]
       Name grep
       Match kube.*
       Exclude log /GET \/healthz.*200/
   필드 프루닝:
   [FILTER]
       Name nest / record_modifier
       Remove_key kubernetes_labels_pod-template-hash
③ 백엔드: 인덱싱 최소화, 보존 정책, 콜드 티어

측정: 노드당 초당 로그 라인 수 × 평균 크기 × 노드 수 × 보존일
     = 저장 비용 (그리고 인덱싱하면 2~3배)
EOF
```

## Step 7. 산출물 — 관측 심층 트랙(11~14) 종합

```markdown
# 세 신호를 잇는 최소 요구사항
| 신호 | 도구 | 필수 설정 |
|------|------|-----------|
| 메트릭 | Prometheus(11) | 저카디널리티 라벨, exemplar 활성화 |
| 트레이스 | OTel(12)+Jaeger(13) | 컨텍스트 전파 무결성, tail 샘플링, 시맨틱 컨벤션 |
| 로그 | Fluent Bit(14) | **구조화 JSON + trace_id 필드**, 버퍼·유실 알람 |
| 접착제 | — | trace_id (로그 필드 ↔ 트레이스 ↔ 메트릭 exemplar) |

# 조사 동선 (11~14의 결론)
알람(메트릭) → exemplar/롱테일 → 트레이스 span 트리 → trace_id로 로그 → 원인
★ 도구를 다 갖춰도 trace_id 하나가 없으면 동선이 끊깁니다 (06 사고 사례)
```

## 정리

```bash
bash cleanup.sh
```
