# Lab 02 — 열린 세계: vegeta, 착시 재현, 법칙 검증

lab-01은 closed 모델(VU 고정)이었습니다. 이번엔 **도착률을 고정**하는 open 모델로 같은 표적을 다시 재고, 두 모델의 답이 갈라지는 지점 — coordinated omission — 을 직접 만든 뒤, Little's Law를 예측 도구로 써봅니다.

전제: lab-01의 podinfo(2×100m)와 무릎 값(§Step 6). 아래에서 `KNEE`를 자신의 실측값으로.

## Step 1. vegeta 계단 — "정확히 N rps"의 세계

```bash
# vegeta는 응답을 기다리지 않습니다 — 매초 정확히 -rate 발사 (open)
for RATE in 200 500 1000; do
  echo "════════ rate=$RATE rps ════════"
  kubectl run vegeta --rm -i --restart=Never -n loadlab \
    --image=peterevans/vegeta:latest --requests=cpu=500m -- sh -c \
    "echo 'GET http://podinfo.loadlab.svc:9898/' | vegeta attack -rate=$RATE -duration=60s | vegeta report"
done
```

각 단계에서 기록: `Success ratio`, `Latencies [p50, p99]`, 실제 `Requests rate`.

예상 패턴:
- **무릎 아래** rate: p99가 lab-01 선형 구간과 비슷 — 두 모델이 합의
- **무릎 위** rate: p99가 초 단위로 폭발 + Success 하락 — closed에선 보이지 않던 광경 (미완료 요청이 쌓이는 현실)

✅ open 모델의 정직함: 서버가 느려져도 **요청은 계속 도착합니다** — 무릎 위의 세계가 어떤 모습인지 보여줍니다.

## Step 2. 착시 재현 — 같은 처리율, 다른 보고서

lab-01에서 VU 120일 때의 goodput(≈무릎값)을 확인하고, **같은 숫자**를 open으로 쏩니다:

```bash
# ① closed의 보고서 (lab-01 Step 3의 VUS=120 결과 재사용 — p99 기록)
# ② open으로 같은 rate를:
KNEE=800   # ← 자신의 무릎 실측값 + 10% 정도로
kubectl run vegeta --rm -i --restart=Never -n loadlab \
  --image=peterevans/vegeta:latest --requests=cpu=500m -- sh -c \
  "echo 'GET http://podinfo.loadlab.svc:9898/' | vegeta attack -rate=$KNEE -duration=60s | vegeta report"
```

비교표를 채워라:

```markdown
| 모델 | 처리율 | p99 | 오류 | 결론이 주는 인상 |
|------|--------|-----|------|----------------|
| closed (VU120) | ~무릎값 | 수백ms~ | ~0% | "좀 느리지만 견딘다" |
| open (rate=무릎+10%) | ~무릎값 | 수 초 | >0% | "무너진다" |
```

✅ **같은 서버, 같은 처리율인데 결론이 다릅니다.** closed는 서버가 느려지면 스스로 발사를 늦춰 고통을 측정에서 누락합니다(coordinated omission). "유입이 N rps일 때 견디는가"라는 용량 질문의 답은 open 쪽입니다 — closed의 보고서로 이 질문에 답하면 낙관 편향된 거짓말이 됩니다.

## Step 3. Little's Law를 예측기로 — 지연을 알면 처리율이 계산됩니다

podinfo의 지연 주입 엔드포인트로 W를 고정하면, closed 모델의 처리율은 **실험 전에 계산**됩니다:

```
L = λ × W  →  λ = L / W  →  VU 50, 지연 2초 = 초당 25 요청. 예외 없음.
```

```bash
# 스크립트의 표적만 /delay/2로 바꾼 버전
sed 's|9898/|9898/delay/2|' load.js > delay.js
kubectl create configmap k6-delay -n loadlab --from-file=load.js=delay.js
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata: { name: k6-law, namespace: loadlab }
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: k6
        image: grafana/k6:0.57.0
        args: [run, /scripts/load.js]
        env: [{ name: VUS, value: "50" }, { name: DURATION, value: "60s" }]
        resources: { requests: { cpu: 500m, memory: 256Mi } }
        volumeMounts: [{ name: s, mountPath: /scripts }]
      volumes: [{ name: s, configMap: { name: k6-delay } }]
EOF
kubectl wait --for=condition=complete job/k6-law -n loadlab --timeout=180s
kubectl logs job/k6-law -n loadlab | grep -E "http_reqs|http_req_duration "
```

예상: `http_reqs ... ≈25/s` (50 VU ÷ 2초). 오차는 몇 % 이내.

✅ 세 가지 실전 능력이 이 산수에서 나옵니다:
1. **VU 산정** — "500 rps를 내려면 VU 몇 개?" = 500 × W
2. **보고서 검산** — RPS·지연·동시성 셋이 L=λW를 안 만족하면 측정을 의심
3. **동시성 요구 계산** — 목표 rps × 지연 = 서버가 감당할 in-flight (워커/커넥션 풀 하한)

## Step 4. 측정 보고서 (이 모듈의 최종 산출물)

```markdown
# 부하 측정 보고서 — podinfo (2 replicas × 100m CPU)
## 방법
- 경로: 클러스터 내부 → Service (ALB 미경유 — 앱 자체 용량)
- 모델: closed(k6)로 무릎 탐색 → open(vegeta)으로 목표율 검증
- 통제: replicas 고정, HPA 없음, 워밍업 15s 제외, 부하기 사용률 <70% 확인
## 결과
- 무릎: __ rps (p99 __ms) / 붕괴: __ rps부터 (p99 __s, 오류 __%)
- 권고 운영 용량: __ rps (무릎의 70%)
- 검산: VU50×delay2 → 25.0 rps 예측 vs __ 실측 ✓
## 다음
- ALB 경유 재측정(14) / RPS 기반 HPA로 무릎 자동 회피(15)
```

## 정리

```bash
bash cleanup.sh
```
