# Lab 02 — OpenCost: 세대별 계량기 달기

노드 단가를 Pod의 예약 비율로 배분하는 계량기를 설치하고 — ns/라벨 단위 금액을 API로 뽑아 **쇼백 표**를 만듭니다. 34의 cost-center 라벨이 드디어 돈이 되는 순간.

## Step 1. Prometheus (계량기의 데이터 원천 — 15의 최소 설치 재사용)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm install prometheus prometheus-community/prometheus -n monitoring --create-namespace \
  --set alertmanager.enabled=false --set prometheus-pushgateway.enabled=false \
  --set server.persistentVolume.enabled=false
kubectl rollout status deploy/prometheus-server -n monitoring --timeout=180s
```

## Step 2. OpenCost 설치

```bash
helm repo add opencost https://opencost.github.io/opencost-helm-chart
helm install opencost opencost/opencost -n opencost --create-namespace \
  --set opencost.prometheus.internal.enabled=false \
  --set opencost.prometheus.external.enabled=true \
  --set opencost.prometheus.external.url=http://prometheus-server.monitoring.svc
kubectl rollout status deploy/opencost -n opencost --timeout=180s
```

OpenCost는 노드의 인스턴스 타입을 보고 **AWS 공시가**를 가져와(온디맨드 기준; CUR 연동 시 실효 단가) requests 비율로 Pod에 배분합니다 — theory §2의 그 산수.

## Step 3. 표적 워크로드 — 라벨 있는 팀과 없는 팀

```bash
# cost-center 라벨이 있는 팀 (34의 규율을 지킨 팀)
kubectl create ns team-a
kubectl label ns team-a cost-center=team-a
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
  namespace: team-a
  labels: { app: worker }
spec:
  replicas: 2
  selector:
    matchLabels: { app: worker }
  template:
    metadata:
      labels: { app: worker }
    spec:
      containers:
        - name: podinfo
          image: ghcr.io/stefanprodan/podinfo:6.7.1
          resources:
            requests: { cpu: 200m, memory: 128Mi }
EOF

# 라벨 없는 무법자 (실무의 절반)
kubectl create ns rogue
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mystery
  namespace: rogue
  labels: { app: mystery }
spec:
  replicas: 1
  selector:
    matchLabels: { app: mystery }
  template:
    metadata:
      labels: { app: mystery }
    spec:
      containers:
        - name: podinfo
          image: ghcr.io/stefanprodan/podinfo:6.7.1
          resources:
            requests: { cpu: 500m, memory: 256Mi }
EOF
sleep 180    # 계량 데이터 축적 (몇 분)
```

## Step 4. 배분 API 심문

```bash
kubectl port-forward -n opencost svc/opencost 9003:9003 &
sleep 3

# ns별 배분 (최근 1시간 창)
curl -s "http://localhost:9003/allocation?window=1h&aggregate=namespace" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)['data'][0]
for k,v in sorted(d.items(), key=lambda x:-x[1].get('totalCost',0)):
    print(f\"{k:30s} cpu≈\${v.get('cpuCost',0):.4f} mem≈\${v.get('ramCost',0):.4f} total≈\${v.get('totalCost',0):.4f}\")"

# 라벨(cost-center) 단위 — 쇼백의 축
curl -s "http://localhost:9003/allocation?window=1h&aggregate=label:cost-center" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)['data'][0]
for k,v in d.items(): print(f'{k:30s} total≈\${v.get(\"totalCost\",0):.4f}')"
kill %1
```

읽을 것 세 가지:

1. **`__idle__`** 항목 — 어느 Pod에도 배분 안 된 노드 여백 = bin-packing(17)의 표적이 금액으로 보입니다
2. **`__unallocated__`** / 라벨 없음 — rogue 팀의 비용이 "주인 없음"에 쌓입니다 → 라벨 규율(34)이 없으면 쇼백이 이 버킷 싸움이 됩니다
3. team-a의 금액이 **requests에 비례**함 — 실사용을 늘려도(부하) 배분 기준은 예약: "예약이 곧 비용"의 실증

## Step 5. 쇼백 표 (산출물)

```markdown
# 월간 비용 쇼백 (예시 양식 — OpenCost allocation을 월 창으로)
| cost-center | 배분액 | requests 갭(lab-01) | 전월 대비 | 권고 |
|-------------|--------|--------------------|----------|------|
| team-a | $__ | __% | | req 다이어트 시 -$__ 예상 |
| (unallocated) | $__ | — | | 라벨 규율 위반 — 소유자 색출 |
| __idle__ | $__ | — | | consolidation 점검(17) |
## 운영 규칙
- 라벨 없는 신규 ns 금지 — 테넌트 패키지(34)가 강제
- idle 비율 > __% 지속 시 NodePool/consolidation 리뷰
- 이 표가 분기 약정(SP) 산정의 근거 문서가 됩니다 (다이어트 후 기준선)
```

## 정리

```bash
bash cleanup.sh
```
