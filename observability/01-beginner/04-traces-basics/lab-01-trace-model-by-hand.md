# Lab 01 — traceparent를 손으로: 모델 체득

> SDK 없이 trace를 손으로 만듭니다 — trace_id를 생성하고, 두 개의 "서비스"(셸 스크립트) 사이에서 traceparent 헤더를 릴레이하고, 기록된 span들로 간트 차트를 손으로 그립니다. 자동화가 대신해 주는 일을 한 번 직접 해 보는 것이 목적입니다.

## 0. 준비

```bash
kind create cluster --name traces

# "span 수집기" 흉내: 받은 JSON을 로그로 찍는 서버 (수집기의 최소 본질)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: span-collector }
spec:
  containers:
    - name: c
      image: hashicorp/http-echo
      args: ["-listen=:9000", "-text=ok"]
EOF
# (http-echo는 body를 저장하진 않으므로, span 기록은 각 서비스가 stdout으로 —
#  02에서 배운 대로 stdout 로그가 곧 우리의 span 저장소입니다)
```

## 1. "서비스 B" — 헤더를 받아 잇는 쪽

```bash
# B: 요청을 받으면 traceparent를 파싱해 자기 span을 stdout에 기록하는 셸 서버
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: svc-b }
spec:
  containers:
    - name: b
      image: busybox
      command: ["sh","-c"]
      args:
        - |
          while true; do
            # 초간단 HTTP 서버: 한 요청 받고 traceparent 줄 추출
            req=$(nc -l -p 8080 -w 5 2>/dev/null | head -20) || continue;
            tp=$(echo "$req" | grep -i "^traceparent:" | tr -d "\r" | awk '{print $2}');
            trace_id=$(echo "$tp" | cut -d- -f2);
            parent=$(echo "$tp" | cut -d- -f3);
            my_span=$(head -c8 /dev/urandom | od -An -tx1 | tr -d " \n");
            start=$(date +%s%3N);
            sleep 0.3;   # 일하는 척 (300ms)
            end=$(date +%s%3N);
            echo "{\"svc\":\"B\",\"trace_id\":\"$trace_id\",\"span_id\":\"$my_span\",\"parent\":\"$parent\",\"name\":\"B: process\",\"start\":$start,\"dur_ms\":$((end-start))}";
          done
EOF
kubectl wait pod/svc-b --for=condition=Ready --timeout=60s
```

## 2. "서비스 A" — trace를 시작하고 전파하는 쪽

```bash
# A: root span을 만들고, B 호출 시 traceparent를 붙입니다
kubectl run svc-a --image=busybox --restart=Never -- sh -c '
  # ① trace 시작: trace_id(16B)·root span_id(8B) 생성
  trace_id=$(head -c16 /dev/urandom | od -An -tx1 | tr -d " \n");
  root_span=$(head -c8 /dev/urandom | od -An -tx1 | tr -d " \n");
  start=$(date +%s%3N);

  sleep 0.1;   # A 자신의 로직 100ms

  # ② B 호출 — ★ traceparent 헤더로 ID 릴레이 (전파의 전부)
  b_call_span=$(head -c8 /dev/urandom | od -An -tx1 | tr -d " \n");
  b_start=$(date +%s%3N);
  printf "GET / HTTP/1.1\r\nHost: svc-b\r\ntraceparent: 00-$trace_id-$b_call_span-01\r\n\r\n" \
    | nc svc-b-ip-placeholder 8080 >/dev/null 2>&1 || true;
  b_end=$(date +%s%3N);

  end=$(date +%s%3N);
  # ③ span 기록 (자식 먼저, 루트 나중 — 실제 SDK도 종료 순)
  echo "{\"svc\":\"A\",\"trace_id\":\"$trace_id\",\"span_id\":\"$b_call_span\",\"parent\":\"$root_span\",\"name\":\"A: call B\",\"start\":$b_start,\"dur_ms\":$((b_end-b_start))}";
  echo "{\"svc\":\"A\",\"trace_id\":\"$trace_id\",\"span_id\":\"$root_span\",\"parent\":null,\"name\":\"A: handle request\",\"start\":$start,\"dur_ms\":$((end-start))}";
' 2>/dev/null || true

# svc-b의 Pod IP를 넣어 실제로 실행
BIP=$(kubectl get pod svc-b -o jsonpath='{.status.podIP}')
kubectl delete pod svc-a --force --grace-period=0 2>/dev/null || true
kubectl run svc-a --image=busybox --restart=Never -- sh -c "
  trace_id=\$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n');
  root_span=\$(head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n');
  start=\$(date +%s%3N); sleep 0.1;
  b_call_span=\$(head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n');
  b_start=\$(date +%s%3N);
  printf 'GET / HTTP/1.1\r\nHost: svc-b\r\ntraceparent: 00-'\$trace_id'-'\$b_call_span'-01\r\n\r\n' | nc $BIP 8080 >/dev/null 2>&1 || true;
  b_end=\$(date +%s%3N); end=\$(date +%s%3N);
  echo \"{\\\"svc\\\":\\\"A\\\",\\\"trace_id\\\":\\\"\$trace_id\\\",\\\"span_id\\\":\\\"\$b_call_span\\\",\\\"parent\\\":\\\"\$root_span\\\",\\\"name\\\":\\\"A: call B\\\",\\\"start\\\":\$b_start,\\\"dur_ms\\\":\$((b_end-b_start))}\";
  echo \"{\\\"svc\\\":\\\"A\\\",\\\"trace_id\\\":\\\"\$trace_id\\\",\\\"span_id\\\":\\\"\$root_span\\\",\\\"parent\\\":null,\\\"name\\\":\\\"A: handle\\\",\\\"start\\\":\$start,\\\"dur_ms\\\":\$((end-start))}\";
"
sleep 8
```

## 3. 흩어진 span을 모아 trace 재구성

```bash
# 두 서비스의 stdout(=우리의 span 저장소)에서 span 수집
kubectl logs svc-a
# {"svc":"A","trace_id":"e3b0...","span_id":"aa11...","parent":"bb22...","name":"A: call B","start":...,"dur_ms":320}
# {"svc":"A","trace_id":"e3b0...","span_id":"bb22...","parent":null,"name":"A: handle","start":...,"dur_ms":430}

kubectl logs svc-b | tail -1
# {"svc":"B","trace_id":"e3b0...","span_id":"cc33...","parent":"aa11...","name":"B: process","start":...,"dur_ms":300}
```

**손으로 트리 조립** — 세 span의 trace_id가 같고(전파 성공!), parent 연결을 따라가면:

```
A: handle (root, 430ms)  ── parent: null
  └ A: call B (320ms)    ── parent: root
      └ B: process (300ms) ── parent: "A: call B"   ← ★ 다른 Pod의 span이 이어짐!

간트 (start 기준 정렬):
A: handle   ██████████████████████ 430ms
A: call B        ████████████████ 320ms   (100ms 지점부터 — A 자신의 로직 후)
B: process        ███████████████ 300ms   (call B의 대부분 = 네트워크+B)
```

**읽기 연습** — "A가 왜 430ms인가요?" → 자기 로직 100ms + B 호출 320ms. "B 호출 320ms 중 B 처리는 300ms" → 나머지 20ms가 네트워크·연결. 이 산수가 트레이스 조사의 전부입니다.

## 4. 방금 손으로 한 일 = SDK가 자동으로 하는 일

```
우리가 한 것                          OTel SDK가 하는 것 (11)
trace_id/span_id 생성          →     자동 (요청 진입 시)
traceparent 헤더 부착           →     HTTP 클라이언트 훅이 자동
받은 헤더 파싱·parent 연결       →     서버 미들웨어가 자동
시각·소요 기록                  →     span 수명 주기 자동
stdout에 기록                  →     Collector로 export (OTLP)
```

## 5. 정리

```bash
kubectl delete pod svc-a svc-b span-collector --force --grace-period=0
# 클러스터는 lab-02에서 계속
```

## 정리

- trace = 같은 trace_id의 span들, 트리는 parent_span_id 연결로 재구성
- 전파의 실체 = **나가는 요청에 traceparent 헤더를 옮겨 붙이는 것** (손으로 해 봄)
- 다른 Pod(B)의 span이 A의 트리에 이어진 것 — 헤더 릴레이 덕분
- 간트 읽기: 부모 시간 = 자기 로직 + 자식들, 자식과의 차이 = 네트워크·오버헤드
- **★ SDK·자동 계측(11)은 이 수작업의 자동화일 뿐 — 원리를 알면 도구는 설정입니다**
