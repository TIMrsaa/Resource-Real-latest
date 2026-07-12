# Lab 02 — 구조화 로깅: 문장에서 데이터로

> 같은 사건을 비구조화 로그와 JSON 로그로 각각 남기는 두 앱을 돌리고, 실제 조사 질문("유저별 실패 상위", "특정 유저의 여정")을 두 로그에 던져 **조사력의 차이**를 체감합니다. 파이프라인 없이 shell로 하며 — 그래서 파이프라인(06~)이 무엇을 자동화해 주는지도 미리 보입니다.

## 0. 준비 (lab-01의 클러스터 이어서)

같은 비즈니스 사건(결제 시도·실패)을 두 형식으로 뿜는 앱들:

```bash
# A: 비구조화 (사람용 문장)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: legacy-app }
spec:
  containers:
    - name: app
      image: busybox
      command: ["sh","-c"]
      args:
        - |
          while true; do
            u=$((RANDOM % 5 + 100));
            amt=$((RANDOM % 900 + 100));
            if [ $((RANDOM % 4)) -eq 0 ]; then
              echo "$(date -Iseconds) ERROR Payment failed for user $u amount $amt won (gateway timeout after 3 retries)";
            else
              echo "$(date -Iseconds) INFO Payment ok user=$u, amount: $amt";
            fi;
            sleep 0.2;
          done
EOF

# B: 구조화 (JSON)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: modern-app }
spec:
  containers:
    - name: app
      image: busybox
      command: ["sh","-c"]
      args:
        - |
          while true; do
            u=$((RANDOM % 5 + 100));
            amt=$((RANDOM % 900 + 100));
            ts=$(date -Iseconds);
            if [ $((RANDOM % 4)) -eq 0 ]; then
              echo "{\"ts\":\"$ts\",\"level\":\"error\",\"event\":\"payment_failed\",\"user_id\":$u,\"amount\":$amt,\"reason\":\"gateway_timeout\",\"retries\":3}";
            else
              echo "{\"ts\":\"$ts\",\"level\":\"info\",\"event\":\"payment_ok\",\"user_id\":$u,\"amount\":$amt}";
            fi;
            sleep 0.2;
          done
EOF
kubectl wait pod/legacy-app pod/modern-app --for=condition=Ready --timeout=60s
sleep 30   # 로그 쌓기
```

주목: A의 형식이 **일관되지도 않습니다** — 실패 줄은 `user 100 amount 500`, 성공 줄은 `user=100, amount: 500`. 실무 비구조 로그의 현실입니다(개발자마다 스타일이 다름).

## 1. 질문 ① — "실패가 몇 건이야?"

```bash
# A (비구조): ERROR 단어로 grep — 이건 그럭저럭 됩니다
kubectl logs legacy-app | grep -c ERROR
# 37

# B (JSON): 필드로 정확히
kubectl logs modern-app | grep -c '"level":"error"'
# 41
```

단순 카운트는 둘 다 됩니다. 차이는 다음부터.

## 2. 질문 ② — "유저별 실패 상위는?"

```bash
# A (비구조): 정규식 파싱 — 형식을 알아내서 짜야 합니다
kubectl logs legacy-app | grep ERROR | sed 's/.*user \([0-9]*\).*/\1/' | sort | uniq -c | sort -rn
#   12 103
#    9 101 ...
# 됐지만: "user " 뒤 숫자라는 형식 지식에 의존 — 성공 줄은 user=라서 이 정규식이 안 맞음!
# 형식이 바뀌면(개발자가 문구 수정) 이 쿼리는 조용히 깨집니다

# B (JSON): 필드 추출 — 형식 지식 불필요
kubectl logs modern-app | grep '"event":"payment_failed"' | \
  sed 's/.*"user_id":\([0-9]*\).*/\1/' | sort | uniq -c | sort -rn
#   14 102
#   10 104 ...
# (shell이라 sed를 썼지만, 파이프라인·저장소에선 user_id 필드 group by 한 줄)
```

## 3. 질문 ③ — "유저 103의 전체 여정(성공+실패)을 시간순으로"

```bash
# A (비구조): 성공 줄은 "user=103", 실패 줄은 "user 103" — 두 패턴 OR
kubectl logs legacy-app | grep -E "user[= ]103" | head -5
# → 패턴을 아는 사람만 가능. "user 1034"도 잘못 걸리는 함정(word boundary)…

# B (JSON): 필드 일치
kubectl logs modern-app | grep '"user_id":103[,}]' | head -5
# → 필드 경계가 명확 ("user_id":1034는 안 걸림)
```

**체감 포인트** — 비구조 로그의 조사는 **형식 고고학**(이 개발자는 어떻게 썼더라?)이고, 형식 변경에 조용히 깨집니다. JSON은 필드 계약이라 안정적이고, 저장소(Loki·CW Logs Insights·OpenSearch)에서는 이 모든 것이 쿼리 언어 한 줄이 됩니다:

```
# 미리보기 — 같은 질문이 파이프라인 위에서는:
CloudWatch Logs Insights (13):
  filter event="payment_failed" | stats count() by user_id | sort desc
Loki LogQL (12):
  {app="modern"} | json | event="payment_failed"  → 라벨·필드 필터
OpenSearch (18):
  event:payment_failed 를 user_id로 terms aggregation
```

## 4. 구조화 설계 리뷰 — B도 완벽하지 않습니다

theory 6절의 원칙으로 B를 리뷰해 보라:

```
잘한 것:
  ✓ event 이름 (payment_failed — 문장 아님)
  ✓ 값은 필드 (user_id·amount·reason·retries)
  ✓ 레벨 분리

빠진 것 (실무라면 추가):
  ✗ trace_id/request_id — 이 실패와 게이트웨이 로그를 이을 실 (12의 상관!)
  ✗ 서비스 식별(service·version) — 여러 서비스가 섞이면 누구 로그인지
    (단, Pod 라벨은 수집기가 붙여줄 수 있음 — 06 kubernetes 필터)
  ✗ 필드 규약 문서화 — 팀마다 userId/user_id/uid면 조인 불가
```

**핵심** — 구조화는 형식(JSON)이 아니라 **계약**(어떤 필드를 어떤 이름으로)입니다. 조직 공통 필드 규약(trace_id·service·env 등)이 있어야 서비스 간 조인이 됩니다.

## 5. 정리

```bash
kubectl delete pod legacy-app modern-app --force --grace-period=0
kind delete cluster --name logging
```

## 정리

- 단순 카운트는 grep도 되지만, **집계·필드 일치·여정 추적**부터 비구조는 형식 고고학
- 비구조 로그의 정규식 쿼리는 문구 변경에 **조용히 깨집니다** — JSON 필드는 계약이라 안정
- 같은 질문이 파이프라인 위에선 쿼리 한 줄 (Logs Insights·LogQL·OpenSearch — 13·12·18)
- 구조화는 JSON이 아니라 **계약**: event 이름·필드 규약·trace_id 같은 공통 컨텍스트
- **★ 로그 품질은 앱 코드에서 결정됩니다 — 파이프라인은 나쁜 원천을 구제하지 못합니다 (01의 신호 품질론)**
