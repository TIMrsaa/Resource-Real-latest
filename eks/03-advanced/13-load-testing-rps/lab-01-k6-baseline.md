# Lab 01 — 포화 곡선 그리기: 베이스라인에서 무릎까지

계단식으로 부하를 올리며 goodput과 p99를 기록해 theory §5의 곡선을 **우리 손으로** 그립니다. 대상은 CPU를 일부러 조인 podinfo — 무릎이 낮아야 실험이 빨리 끝납니다.

## Step 1. 실험 대상 — 변수를 통제한 표적

```bash
kubectl create ns loadlab
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: podinfo, namespace: loadlab }
spec:
  replicas: 2                      # 고정 — HPA 없음 (변수 통제!)
  selector: { matchLabels: { app: podinfo } }
  template:
    metadata: { labels: { app: podinfo } }
    spec:
      containers:
      - name: podinfo
        image: ghcr.io/stefanprodan/podinfo:6.7.1
        ports: [{ containerPort: 9898 }]
        resources:
          requests: { cpu: 100m, memory: 64Mi }
          limits:   { cpu: 100m, memory: 128Mi }    # ★ 일부러 좁은 천장 — 무릎을 낮춥니다
        readinessProbe: { httpGet: { path: /readyz, port: 9898 } }
---
apiVersion: v1
kind: Service
metadata: { name: podinfo, namespace: loadlab }
spec:
  selector: { app: podinfo }
  ports: [{ port: 9898 }]
EOF
kubectl rollout status deploy/podinfo -n loadlab
```

부하기 위치는 **클러스터 안**(Service 직행) — 지금 재는 것은 "앱 자체의 용량"입니다. ALB 경유 경로는 14의 주제.

## Step 2. k6 스크립트 — VU 수를 밖에서 주입

```bash
cat <<'EOF' > load.js
import http from 'k6/http';
import { check } from 'k6';
export const options = {
  scenarios: {
    steady: {
      executor: 'constant-vus',              // closed 모델 (이 랩의 세계관)
      vus: Number(__ENV.VUS || 10),
      duration: __ENV.DURATION || '90s',
    },
  },
  summaryTrendStats: ['avg', 'p(50)', 'p(95)', 'p(99)', 'max'],
  thresholds: { http_req_failed: ['rate<0.01'] },
};
export default function () {
  const r = http.get('http://podinfo.loadlab.svc:9898/');
  check(r, { ok: (x) => x.status === 200 });
}
EOF
kubectl create configmap k6-script -n loadlab --from-file=load.js
```

## Step 3. 계단 실행 — VU 10 → 30 → 60 → 120

```bash
for VUS in 10 30 60 120; do
  kubectl delete job k6-run -n loadlab --ignore-not-found >/dev/null 2>&1; sleep 3
  cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata: { name: k6-run, namespace: loadlab }
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: k6
        image: grafana/k6:0.57.0
        args: [run, /scripts/load.js]
        env: [{ name: VUS, value: "$VUS" }]
        resources: { requests: { cpu: "1", memory: 256Mi } }   # 부하기가 병목이면 안 됩니다!
        volumeMounts: [{ name: s, mountPath: /scripts }]
      volumes: [{ name: s, configMap: { name: k6-script } }]
EOF
  kubectl wait --for=condition=complete job/k6-run -n loadlab --timeout=300s
  echo "════════ VUS=$VUS ════════"
  kubectl logs job/k6-run -n loadlab | grep -E "http_reqs|http_req_duration |http_req_failed|checks"
done
```

실행 중 다른 터미널에서 표적의 상태도 감시:

```bash
watch -n5 "kubectl top pods -n loadlab"    # podinfo CPU가 limit(100m)에 붙는 순간 = 포화 시작
```

## Step 4. 곡선 읽기 — 기록표

각 단계의 로그에서 두 숫자만 옮겨 적습니다 (`http_reqs`의 rate = 처리율, `http_req_duration`의 p(99)):

```markdown
| VUs | goodput (rps) | p50 | p99 | 오류율 | 판정 |
|-----|---------------|-----|-----|-------|------|
| 10  | (예: ~900)    | ~8ms | ~20ms | 0% | 선형 구간 |
| 30  | (예: ~1400)   | ~15ms| ~60ms | 0% | 무릎 접근 |
| 60  | 정체 시작      | ↑   | 수백ms | 0~ | ★ 무릎 |
| 120 | 그대로/하락    | ↑↑  | 초 단위 | >0 | 붕괴 — 큐잉의 수직 상승 |
```

(절대값은 노드/버전에 따라 다릅니다 — **모양**이 답입니다: goodput은 눕고 p99는 서는 지점)

✅ 판독 훈련 세 가지:
1. **용량 = 무릎 직전 goodput** — 120 VU에서 나온 최대값이 아닙니다
2. VU를 늘려도 goodput이 안 늘면, 그 VU들은 **큐에 줄 서 있을 뿐** — Little's Law로 확인: L(=VU) = λ×W이므로 λ가 고정되면 W(지연)가 VU에 비례해 늘어납니다. 기록표에서 VU 2배 ↔ p50 2배가 보이는가요?
3. `kubectl top`에서 podinfo가 100m에 붙은 시점과 무릎이 일치하는가 — 병목의 신원 확인(CPU throttling, k8s 06)

## Step 5. 검산 — 부하기는 결백한가

```bash
kubectl logs job/k6-run -n loadlab | grep -E "dropped_iterations" || echo "드랍 없음"
kubectl top pods -n loadlab   # k6 Pod의 CPU가 요청량(1 CPU) 근처면 부하기 증설 후 재측정
```

✅ theory §6의 폐기 조건 점검 — "부하기가 지쳐서 나온 무릎"은 무릎이 아닙니다.

## Step 6. 베이스라인 기록 (lab-02와 이후 모듈의 기준점)

```markdown
# baseline — podinfo 2×100m, 클러스터 내부 직행
- 무릎: 약 __ rps (VU __에서)  /  무릎 직전 p99: __ ms
- 운영 권고 용량(무릎의 70%): __ rps
- 병목: CPU limit (top에서 확인)  /  부하기 드랍: 없음
```

## 정리

podinfo/스크립트는 lab-02에서 계속 사용 — Job만 정리:

```bash
kubectl delete job k6-run -n loadlab --ignore-not-found
```
