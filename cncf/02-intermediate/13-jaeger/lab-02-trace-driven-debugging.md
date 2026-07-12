# Lab 02 — 트레이스로 장애 좁히기: 조사 동선을 손에 붙입니다

06 사고 사례에서 실패했던 그 동선(알람 → 트레이스 → 로그)을 처음부터 끝까지 밟습니다.

전제: lab-01의 클러스터·데이터, port-forward(16686).

## Step 1. 증상 인지 — 지연 분포에서 롱테일 찾기

```bash
# Jaeger API로 오퍼레이션별 지연 분포를 근사 (UI에서는 산점도로 보입니다)
curl -s "http://localhost:16686/api/traces?service=shop&limit=100" | python3 -c "
import json,sys
d = json.load(sys.stdin)['data']
durs = []
for t in d:
    root = min(t['spans'], key=lambda s: s['startTime'])
    durs.append(root['duration']/1000)
durs.sort()
n = len(durs)
p = lambda q: durs[min(n-1, int(n*q))]
print(f'트레이스 {n}건')
print(f'  p50 = {p(.5):7.1f}ms')
print(f'  p90 = {p(.9):7.1f}ms')
print(f'  p99 = {p(.99):7.1f}ms   ← 롱테일!')
print(f'  max = {durs[-1]:7.1f}ms')
"
```

예상: p50은 수십 ms인데 p99는 600ms 이상 — **평균은 멀쩡한데 꼬리가 아픕니다**(eks 13의 그 문제). 알람이 p99 SLO로 걸려 있다면 여기서 조사가 시작됩니다.

## Step 2. 진입 — 느린 트레이스를 골라냅니다

```bash
SLOW=$(curl -s "http://localhost:16686/api/traces?service=shop&minDuration=500ms&limit=1" | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['data'][0]['traceID'])")
echo "느린 트레이스: $SLOW"

FAST=$(curl -s "http://localhost:16686/api/traces?service=shop&maxDuration=100ms&limit=1" | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['data'][0]['traceID'])")
echo "정상 트레이스: $FAST"
```

## Step 3. span 트리 — critical path의 병목

```bash
show() {
  curl -s "http://localhost:16686/api/traces/$1" | python3 -c "
import json,sys
t = json.load(sys.stdin)['data'][0]
spans = sorted(t['spans'], key=lambda s: s['startTime'])
base = spans[0]['startTime']
total = spans[0]['duration']/1000
print(f'  총 {total:.1f}ms')
for s in spans:
    off = (s['startTime']-base)/1000
    dur = s['duration']/1000
    pct = dur/total*100
    err = ' ❌' if any(tag['key']=='error' and tag['value'] for tag in s.get('tags',[])) else ''
    bar = '█' * max(1, int(pct/4))
    print(f\"    {s['operationName']:16s} +{off:6.1f}ms {dur:6.1f}ms ({pct:4.1f}%) {bar}{err}\")
"
}
echo "=== 정상 트레이스 ==="; show "$FAST"
echo "=== 느린 트레이스 ==="; show "$SLOW"
```

예상: 정상은 db.query와 payment.call이 고르게, 느린 것은 **payment.call이 전체의 90%+** 이고 에러 표시. ✅ **critical path 식별**(theory §4) — 전체 시간을 지배한 구간이 즉시 보입니다(cicd 23의 파이프라인 critical path와 같은 사고).

## Step 4. 비교 — 정상과 무엇이 다른가

```bash
python3 - <<EOF
import json, subprocess
def get(tid):
    out = subprocess.run(["curl","-s",f"http://localhost:16686/api/traces/{tid}"],capture_output=True,text=True).stdout
    t = json.load(__import__('io').StringIO(out))['data'][0]
    return {s['operationName']: s['duration']/1000 for s in t['spans']}, t

slow, ts = get("$SLOW")
fast, tf = get("$FAST")
print("=== 구간별 비교 (느린 vs 정상) ===")
for op in sorted(set(slow)|set(fast)):
    s, f = slow.get(op,0), fast.get(op,0)
    ratio = f"{s/f:.1f}x" if f else "n/a"
    print(f"  {op:16s} {s:7.1f}ms vs {f:6.1f}ms   ({ratio})")

# 태그 diff — 어떤 요청이 느린가?
def tags(t, op):
    for s in t['spans']:
        if s['operationName']==op:
            return {x['key']: x['value'] for x in s.get('tags',[]) if x['key'].startswith('myco')}
    return {}
print()
print("느린 트레이스 root 태그:", tags(ts,'checkout'))
print("정상 트레이스 root 태그:", tags(tf,'checkout'))
EOF
```

예상: `payment.call`만 10~20배 느리고, 느린 쪽의 `myco.user.tier=gold`. ✅ **가설이 좁혀졌습니다**: gold 티어의 결제 경로에 문제가 있습니다(태그가 조사를 안내한 것 — 시맨틱 컨벤션과 커스텀 네임스페이스의 값어치).

## Step 5. 로그로 넘어가기 — 행 간 연결

```bash
cat <<EOF
동선의 마지막 홉 (06의 "행 간 연결"):
  1. 이 span의 trace_id: $SLOW
  2. 로그 시스템에서 trace_id 필드로 조회:
       {trace_id="$SLOW"}                      (Loki/LogQL)
       trace_id:"$SLOW"                        (Elasticsearch)
  3. 그 시각 payment 서비스의 로그 → "upstream gateway timeout after 600ms"
  4. 원인 확정

★ 이것이 가능하려면: 앱의 로그에 trace_id가 구조화 필드로 들어가야 합니다
   (OTel의 로그 계측 또는 로깅 라이브러리에 컨텍스트 주입 — 12)
   06의 사고 사례가 실패한 지점이 정확히 여기였습니다 (요청 ID가 서비스마다 달랐습니다)
EOF
```

## Step 6. 서비스 그래프 — 트레이스에서 메트릭 파생

```bash
cat <<'EOF'
Jaeger의 Service Performance Monitoring(SPM):
  span에서 서비스 간 호출 수·지연·에러율을 집계 → 메트릭으로 저장(Prometheus)
  → "어느 서비스 쌍의 에러율이 튀는가"를 트레이스 없이도 봅니다

같은 아이디어의 OTel 구현: spanmetrics connector
  traces → (spanmetrics) → metrics  파이프라인
  즉 12의 Collector에서 트레이스로부터 RED 메트릭(Rate·Error·Duration)을 생성

함의: 트레이스는 샘플링해도(12) 메트릭은 전수여야 한다면 —
      spanmetrics를 샘플링 '앞'에 두어야 합니다 (processors 순서!)
EOF
```

✅ 12의 processors 순서 규칙이 여기서 실무 결정이 됩니다: `spanmetrics` → `tail_sampling` 순이어야 전수 RED 메트릭 + 선별 트레이스를 동시에 얻습니다.

## Step 7. 산출물 — 조사 동선 카드

```markdown
# 트레이스 기반 조사 동선 (오늘 밟은 것)
1. 알람: SLO(p99) 위반 — 메트릭(11)
2. 진입: 지연 롱테일 선택 (또는 exemplar로 trace_id 직행)
3. span 트리: critical path의 병목 구간 식별
4. 비교: 정상 트레이스와 diff — 구간·태그의 차이
5. 로그: trace_id로 조회 → 원인 문장
6. 파생: SPM/spanmetrics로 서비스 그래프 상시 감시

# 전제 조건 (없으면 동선이 끊깁니다)
- [ ] 컨텍스트 전파 무결성 (12 lab-01)
- [ ] 로그에 trace_id 구조화 필드
- [ ] 메트릭에 exemplar (Prometheus + OTel)
- [ ] tail 샘플링으로 에러·느린 것 보존 (12 lab-02)
- [ ] 시맨틱 컨벤션 + 커스텀 태그의 네임스페이스
```

## 정리

```bash
kill %1 2>/dev/null || true
bash cleanup.sh
```
