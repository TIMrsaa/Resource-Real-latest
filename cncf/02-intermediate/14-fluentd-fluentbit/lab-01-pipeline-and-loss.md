# Lab 01 — 로그의 경로를 따라가고, 유실을 재현합니다

컨테이너 stdout이 어디에 앉는지 눈으로 보고, 백프레셔로 로그가 조용히 사라지는 순간을 만듭니다.

전제: kind, kubectl, helm, docker.

## Step 1. 클러스터와 로그 파일의 실체

```bash
kind create cluster --name logs -q
kubectl run talker --image=busybox --restart=Never -- sh -c 'i=0; while true; do i=$((i+1)); echo "line $i"; sleep 0.2; done'
kubectl wait --for=condition=ready pod/talker --timeout=60s
sleep 5

# 노드(=도커 컨테이너) 안에서 실제 로그 파일 확인
docker exec logs-control-plane sh -c '
echo "=== /var/log/containers (심볼릭 링크) ==="
ls -l /var/log/containers/ | grep talker
echo ""
echo "=== 실제 파일 (CRI 로그 형식) ==="
find /var/log/pods -name "*.log" | grep talker | head -1 | xargs head -3
'
```

예상: `2026-07-10T...Z stdout F line 1` 형식 — **타임스탬프 + 스트림 + 태그(F=full, P=partial) + 내용**. ✅ 이것이 CRI 로그 형식이고, 에이전트의 parser가 첫 번째로 벗겨내는 껍질입니다(theory §1).

```bash
docker exec logs-control-plane sh -c 'cat /var/lib/kubelet/config.yaml | grep -i containerLog || echo "기본값: containerLogMaxSize=10Mi, MaxFiles=5"'
echo "→ 첫 유실 지점: 이 로테이션을 에이전트가 못 따라가면 파일이 먼저 사라진다"
```

## Step 2. Fluent Bit 설치 — 에이전트

```bash
helm repo add fluent https://fluent.github.io/helm-charts >/dev/null 2>&1
kubectl create ns logging
cat > /tmp/fb-values.yaml <<'EOF'
config:
  service: |
    [SERVICE]
        Flush 1
        Log_Level info
        Parsers_File /fluent-bit/etc/parsers.conf
        storage.metrics on
        HTTP_Server On
        HTTP_Listen 0.0.0.0
        HTTP_Port 2020
  inputs: |
    [INPUT]
        Name tail
        Path /var/log/containers/*.log
        multiline.parser cri
        Tag kube.*
        Mem_Buf_Limit 5MB
        storage.type memory
        DB /var/log/flb_kube.db
  filters: |
    [FILTER]
        Name kubernetes
        Match kube.*
        Merge_Log On
        Keep_Log Off
        K8S-Logging.Parser On
  outputs: |
    [OUTPUT]
        Name stdout
        Match kube.*
        Format json_lines
EOF
helm install fb fluent/fluent-bit -n logging -f /tmp/fb-values.yaml >/dev/null
kubectl -n logging rollout status ds/fb-fluent-bit --timeout=180s
```

## Step 3. 파이프라인 통과 확인 — k8s 메타가 붙습니다

```bash
sleep 15
kubectl -n logging logs ds/fb-fluent-bit --tail=3 | python3 -c "
import json,sys
for line in sys.stdin:
    try: d = json.loads(line)
    except: continue
    k = d.get('kubernetes', {})
    print(f\"log: {d.get('log','').strip()[:30]}\")
    print(f\"  pod:       {k.get('pod_name')}\")
    print(f\"  namespace: {k.get('namespace_name')}\")
    print(f\"  container: {k.get('container_name')}\")
    break
"
```

예상: 원본 로그 + `kubernetes.*` 메타데이터. ✅ **filter가 K8s API에서 Pod 메타를 조회해 붙였습니다**(theory §2) — 앱은 "line N"만 뱉었는데 어디서 온 로그인지가 완성됐습니다. (12의 Collector k8sattributes와 같은 아이디어.)

## Step 4. 멀티라인 함정 재현 — 스택트레이스가 조각납니다

```bash
kubectl run javaish --image=busybox --restart=Never -- sh -c '
while true; do
  echo "Exception in thread \"main\" java.lang.RuntimeException: boom"
  echo "    at com.example.Service.pay(Service.java:42)"
  echo "    at com.example.Controller.checkout(Controller.java:17)"
  echo "    at java.base/java.lang.Thread.run(Thread.java:840)"
  sleep 10
done'
kubectl wait --for=condition=ready pod/javaish --timeout=60s
sleep 20

kubectl -n logging logs ds/fb-fluent-bit --tail=40 | grep -c "at com.example" || true
echo "→ 스택트레이스 각 줄이 '별도의 로그 레코드'로 잡혔다면 멀티라인 파서가 없는 것"
cat <<'EOF'

해결책 두 가지:
  ① Fluent Bit multiline filter — 첫 줄 패턴(예: ^Exception|^\S)으로 시작 감지 후 병합
     [FILTER]
         Name multiline
         Match kube.*
         multiline.key_content log
         mode partial_message      # 또는 커스텀 parser
  ② ★ 근본: 앱이 처음부터 구조화 JSON 한 줄로 (스택트레이스는 필드 하나에) — lab-02
EOF
```

## Step 5. 백프레셔와 유실 재현 — 조용한 사라짐

```bash
# 매우 작은 버퍼 + 폭발적 로그 → drop을 강제
cat > /tmp/fb-tiny.yaml <<'EOF'
config:
  service: |
    [SERVICE]
        Flush 5
        Log_Level info
        storage.metrics on
        HTTP_Server On
        HTTP_Listen 0.0.0.0
        HTTP_Port 2020
  inputs: |
    [INPUT]
        Name tail
        Path /var/log/containers/flooder*.log
        multiline.parser cri
        Tag kube.*
        Mem_Buf_Limit 1KB
        storage.type memory
  outputs: |
    [OUTPUT]
        Name stdout
        Match kube.*
        Format json_lines
        Retry_Limit 1
EOF
helm upgrade fb fluent/fluent-bit -n logging -f /tmp/fb-tiny.yaml >/dev/null
kubectl -n logging rollout status ds/fb-fluent-bit --timeout=120s

# 초당 수천 줄을 뱉는 앱
kubectl run flooder --image=busybox --restart=Never -- sh -c '
i=0; while [ $i -lt 50000 ]; do i=$((i+1)); echo "flood $i $(date +%s%N)"; done; sleep 3600'
kubectl wait --for=condition=ready pod/flooder --timeout=60s
sleep 30

echo "=== Fluent Bit 자체 메트릭: 유실 지표 ==="
kubectl -n logging exec ds/fb-fluent-bit -- wget -qO- http://localhost:2020/api/v1/metrics 2>/dev/null | \
  python3 -c "
import json,sys
m = json.load(sys.stdin)
for name, v in m.get('input',{}).items():
    print(f'  input {name}: records={v.get(\"records\")} bytes={v.get(\"bytes\")}')
for name, v in m.get('output',{}).items():
    print(f'  output {name}: proc={v.get(\"proc_records\")} errors={v.get(\"errors\")} retries_failed={v.get(\"retries_failed\")} dropped={v.get(\"dropped_records\")}')
" 2>/dev/null || kubectl -n logging logs ds/fb-fluent-bit --tail=5 | grep -i "pause\|drop\|overlimit"

kubectl -n logging logs ds/fb-fluent-bit --tail=50 | grep -iE "pause|over limit|dropped" | head -3
```

예상: `[warn] [input] tail.0 paused (mem buf overlimit)` 또는 dropped 카운터 증가. ✅ **로그가 조용히 사라졌습니다** — 앱은 정상이고, 에러도 없고, 그저 로그가 적을 뿐(theory §3). 이것이 장애 중에 벌어지면 조사가 불가능해집니다.

## Step 6. 방어 설계 — 디스크 버퍼와 알람

```bash
cat <<'EOF'
# 방어 1: 디스크 버퍼 (메모리 초과분을 파일로)
[SERVICE]
    storage.path /var/log/flb-storage/
    storage.max_chunks_up 128
[INPUT]
    storage.type filesystem          # ★ 메모리 → 파일
    Mem_Buf_Limit 50MB

# 방어 2: 유실을 '조용하지 않게' — 알람 대상 메트릭
fluentbit_input_records_total          입력 레코드
fluentbit_output_proc_records_total    처리 레코드
fluentbit_output_retries_failed_total  ★ 재시도 실패(=유실)
fluentbit_output_dropped_records_total ★ 드롭
storage 관련 chunks up/down            버퍼 사용률
→ input - output 의 지속적 격차 = 유실 진행 중

# 방어 3: 볼륨 자체를 줄입니다 (theory §6 — 가장 싼 곳부터)
  앱 로그 레벨 → 에이전트 필터 drop(헬스체크 등) → 백엔드 인덱싱·보존
EOF
```

## Step 7. 산출물

```markdown
# 로그 파이프라인 진단 카드
| 증상 | 층 | 확인 |
|------|----|------|
| 특정 Pod 로그가 안 옴 | input | tail Path 패턴, DB(오프셋) 파일, 파일 권한 |
| 스택트레이스가 줄마다 분리 | parser | multiline 파서 (또는 앱의 구조화 로깅) |
| k8s 메타가 없음 | filter | kubernetes filter, RBAC(Pod 조회 권한) |
| 로그가 띄엄띄엄 사라짐 | buffer | Mem_Buf_Limit, dropped/retries_failed 메트릭 |
| 백엔드 429/타임아웃 | output | 재시도·백오프, 백엔드 용량, 큐(Kafka) 도입 |
| 오래된 로그가 없음 | kubelet | containerLogMaxSize 로테이션 (에이전트가 못 따라감) |
```

## 정리

lab-02에서 계속. 유지.
