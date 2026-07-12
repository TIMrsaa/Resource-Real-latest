# Lab 02 — 끊긴 전파: 조각난 트레이스의 조사 불능

> 전파가 끊기는 대표 상황 두 가지(미전파 서비스, 비동기 큐)를 재현해, 트리가 조각날 때 조사가 어떻게 무력해지는지 체감합니다. lab-01의 수작업 모델을 그대로 확장합니다.

## 0. 준비 (lab-01 클러스터 이어서)

시나리오: `A → B → C` 3단 호출. 단, **B가 전파를 안 합니다**(계측 안 된 레거시).

## 1. 끊는 서비스 B — 받기만 하고 안 넘김

```bash
# C: lab-01의 B와 같은 역할 (받은 traceparent를 기록)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: svc-c }
spec:
  containers:
    - name: c
      image: busybox
      command: ["sh","-c"]
      args:
        - |
          while true; do
            req=$(nc -l -p 8080 -w 5 2>/dev/null | head -20) || continue;
            tp=$(echo "$req" | grep -i "^traceparent:" | tr -d "\r" | awk '{print $2}');
            if [ -z "$tp" ]; then
              # ★ 헤더가 없으면? 새 trace를 시작할 수밖에 (고아)
              trace_id=$(head -c16 /dev/urandom | od -An -tx1 | tr -d " \n");
              parent="null(orphan!)";
            else
              trace_id=$(echo "$tp" | cut -d- -f2); parent=$(echo "$tp" | cut -d- -f3);
            fi
            echo "{\"svc\":\"C\",\"trace_id\":\"$trace_id\",\"parent\":\"$parent\",\"name\":\"C: work\"}";
          done
EOF

# B(레거시): 받은 요청을 C로 중계하지만 traceparent를 옮기지 않습니다!
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: svc-b-legacy }
spec:
  containers:
    - name: b
      image: busybox
      command: ["sh","-c"]
      args:
        - |
          while true; do
            req=$(nc -l -p 8080 -w 5 2>/dev/null | head -20) || continue;
            tp=$(echo "$req" | grep -i "^traceparent:" | tr -d "\r" | awk '{print $2}');
            echo "{\"svc\":\"B\",\"received_traceparent\":\"$tp\",\"note\":\"received but NOT forwarding\"}";
            # ★ C 호출 — traceparent 없이! (계측 안 된 앱의 현실)
            printf "GET / HTTP/1.1\r\nHost: svc-c\r\n\r\n" | nc SVC_C_IP 8080 >/dev/null 2>&1 || true;
          done
EOF
kubectl wait pod/svc-c --for=condition=Ready --timeout=60s
CIP=$(kubectl get pod svc-c -o jsonpath='{.status.podIP}')
kubectl get pod svc-b-legacy -o yaml | sed "s/SVC_C_IP/$CIP/" | kubectl replace --force -f -
kubectl wait pod/svc-b-legacy --for=condition=Ready --timeout=60s
```

## 2. A가 trace를 시작해 호출

```bash
BIP=$(kubectl get pod svc-b-legacy -o jsonpath='{.status.podIP}')
kubectl run svc-a2 --image=busybox --restart=Never -- sh -c "
  trace_id=\$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n');
  span=\$(head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n');
  echo \"{\\\"svc\\\":\\\"A\\\",\\\"trace_id\\\":\\\"\$trace_id\\\",\\\"name\\\":\\\"A: start\\\"}\";
  printf 'GET / HTTP/1.1\r\nHost: b\r\ntraceparent: 00-'\$trace_id'-'\$span'-01\r\n\r\n' | nc $BIP 8080 >/dev/null 2>&1 || true;
"
sleep 10
```

## 3. 조각난 결과 확인

```bash
echo "=== A의 trace_id ==="; kubectl logs svc-a2 | grep -o '"trace_id":"[a-f0-9]*"'
# "trace_id":"7f3a9c..."

echo "=== B: 받긴 받았다 ==="; kubectl logs svc-b-legacy | tail -1
# {"svc":"B","received_traceparent":"00-7f3a9c...-...-01","note":"received but NOT forwarding"}

echo "=== C: 고아가 됐다 ==="; kubectl logs svc-c | tail -1
# {"svc":"C","trace_id":"d08e12...","parent":"null(orphan!)",...}
#              └── A와 다른 trace_id! 연결 증발
```

**결과 해석** — 백엔드(Jaeger 등)에서 이 상황은:

```
trace 7f3a9c...: [A: start] → [B 호출]   ← 여기서 뚝. "B 다음이 없음"
trace d08e12...: [C: work]                ← 고아 trace. 어디서 왔는지 모름

조사자의 시야:
  "A→B는 보이는데 C가 왜 호출됐는지, C가 느리면 어느 요청 때문인지 알 수 없다"
  → C에서 장애가 나면 다시 팀 간 떠넘기기로 회귀 (트레이스 도입 전과 동일)
  → 반쪽 전파 = 반쪽 가치. "일부 서비스만 계측"의 함정
```

## 4. 비동기 경계 — 두 번째 끊김 (개념 재현)

큐를 거치면 HTTP 헤더가 없습니다. 메시지에 실어야 합니다:

```bash
# 큐 흉내: A가 "메시지"를 파일(공유 볼륨 대신 로그)로 넘긴다고 합시다
# 나쁜 메시지 (전파 누락):
echo '{"order_id": 123, "amount": 5000}'
# → 소비자는 trace를 이을 방법이 없습니다 (고아)

# 좋은 메시지 (컨텍스트를 메시지에 실음):
echo '{"order_id": 123, "amount": 5000,
      "traceparent": "00-7f3a9c...-aa11...-01"}'
# → 소비자가 이 필드를 읽어 이어감 (OTel 메시징 계측이 자동화하는 것)
# cncf 40의 CloudEvents라면: extension 속성으로 traceparent 릴레이
```

**핵심** — 비동기에서 전파는 "헤더"가 아니라 **메시지 속 데이터**입니다. 큐 도입 시 트레이스가 끊겼다면 십중팔구 이 누락입니다(theory 4절 ②).

## 5. 도입 검증 절차 (실무 체크리스트)

```
트레이스 도입/변경 후 반드시:
  □ 대표 경로로 요청 1개 → 백엔드에서 trace 열기
  □ 기대한 모든 서비스의 span이 한 트리에 있나요?
  □ 조각(고아 trace)이 생기지 않았나요?
  □ 큐·배치 경계 너머도 이어지나요?
  □ (폴리글랏) 언어 간 전파 형식이 통일됐나 (W3C로)?
→ "설치했다"가 아니라 "실이 끝까지 이어진다"가 완료 기준
```

## 6. 정리

```bash
kubectl delete pod svc-a2 svc-b-legacy svc-c --force --grace-period=0 2>/dev/null || true
kind delete cluster --name traces
```

## 정리

- 전파를 안 하는 서비스 하나(B)가 실을 끊고 — 그 뒤 전부(C)가 **고아 trace**가 됩니다
- 고아 trace는 "어느 요청 때문인지"에 답 못 함 → 그 구간은 도입 전(떠넘기기)으로 회귀
- 비동기 경계의 전파는 헤더가 아니라 **메시지 속 필드** — 큐에서 끊기는 이유
- 완료 기준은 "설치"가 아니라 "실이 끝까지 이어짐" — 대표 경로 검증 필수
- **★ 트레이스의 가치는 가장 약한 고리가 정합니다 — 반쪽 전파는 반쪽 가치**
