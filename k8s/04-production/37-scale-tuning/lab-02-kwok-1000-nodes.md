# Lab 02 — kwok로 1000노드: 대규모 스케줄링 실측 (로컬, 무료)

> **환경**: 로컬 kind (WSL2/Docker). 1000개의 **가짜 노드**(kubelet 없음, kwok가 상태만 연기)를 등록하면 — 스케줄러/API 서버/컨트롤러는 진짜 1000노드 클러스터처럼 일합니다. 비용 0원.

## Step 1. kind + kwok 설치

```bash
kind create cluster --name scale-lab
KWOK_VER=$(curl -s https://api.github.com/repos/kubernetes-sigs/kwok/releases/latest | grep tag_name | cut -d'"' -f4)
kubectl apply -f https://github.com/kubernetes-sigs/kwok/releases/download/$KWOK_VER/kwok.yaml
kubectl apply -f https://github.com/kubernetes-sigs/kwok/releases/download/$KWOK_VER/stage-fast.yaml
kubectl -n kube-system rollout status deploy/kwok-controller
```

> `stage-fast.yaml`이 "가짜 노드 위 Pod는 즉시 Running으로 연기하라"는 대본(Stage)입니다.

## Step 2. 가짜 노드 1000개 등록

```bash
cat > fake-node.yaml <<'EOF'
apiVersion: v1
kind: Node
metadata:
  name: kwok-node-__N__
  annotations:
    kwok.x-k8s.io/node: fake          # kwok가 이 노드를 연기
  labels:
    type: kwok
spec:
  taints:                             # 진짜 워크로드(DaemonSet 등)가 못 오게
  - key: kwok.x-k8s.io/node
    value: fake
    effect: NoSchedule
status:
  allocatable: { cpu: "32", memory: 256Gi, pods: "110" }
  capacity:    { cpu: "32", memory: 256Gi, pods: "110" }
EOF

time for i in $(seq 1 1000); do
  sed "s/__N__/$i/" fake-node.yaml | kubectl apply -f - > /dev/null
done
kubectl get nodes | grep -c kwok    # → 1000
kubectl get nodes -l type=kwok | head -3
```

✅ **노드 1001개 클러스터**가 됐습니다(진짜 1 + 가짜 1000). 등록에 걸린 시간 자체가 "API 서버에 객체 1000개 쓰기"의 실측이기도 합니다.

## Step 3. 5000 Pod 투하 — 스케줄러 처리량 측정

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: horde }
spec:
  replicas: 5000
  selector: { matchLabels: { app: horde } }
  template:
    metadata: { labels: { app: horde } }
    spec:
      nodeSelector: { type: kwok }
      tolerations:
      - { key: kwok.x-k8s.io/node, operator: Exists }
      containers:
      - name: c
        image: fake          # kwok가 연기하므로 진짜 이미지 불필요
        resources: { requests: { cpu: 100m, memory: 128Mi } }
EOF

# 진행 관찰
kubectl get deploy horde -w
```

전부 Ready가 되면 **스케줄링 처리량을 타임스탬프로 계산**:

```bash
kubectl get pods -l app=horde -o json | python3 -c "
import json,sys
from datetime import datetime
ts=[]
for p in json.load(sys.stdin)['items']:
    for c in p['status'].get('conditions',[]):
        if c['type']=='PodScheduled' and c['status']=='True':
            ts.append(datetime.fromisoformat(c['lastTransitionTime'].replace('Z','+00:00')))
dur=(max(ts)-min(ts)).total_seconds() or 1
print(f'{len(ts)} pods / {dur:.0f}s = {len(ts)/dur:.0f} pods/s')"
```

예상: `5000 pods / NNs = 100~300 pods/s` (로컬 사양에 따라 다름)

✅ **이 숫자가 theory §4의 "초당 수십~수백"의 실측값.** 대량 배포/장애 복구 시 "Pod 5000개면 최소 N초의 Pending은 물리 법칙"임을 체감 — 모니터링 알림 임계값을 정할 근거가 됩니다.

## Step 4. 분포 확인 — 스케줄러는 일을 잘했나

```bash
# 노드별 Pod 수의 최소/최대 (균형 정도)
kubectl get pods -l app=horde -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' \
  | sort | uniq -c | sort -n | awk 'NR==1{print "min:",$1} END{print "max:",$1}'
```

예상: min/max가 비슷(약 5개 안팎) — 기본 스코어링(LeastAllocated 계열)이 고르게 폈습니다. 1000노드 중 **일부만 채점**(percentageOfNodesToScore 적응형)했는데도 분포가 준수합니다 — "충분히 좋은 노드를 빨리"의 실증.

## Step 5. churn 부하 — watch 증폭 체감

```bash
# 5000 Pod를 한 번에 갈아치우기 (rolling) — API/watch에 이벤트 폭풍
time kubectl patch deploy horde -p '{"spec":{"template":{"metadata":{"labels":{"v":"2"}}}}}'
kubectl rollout status deploy/horde --timeout=600s
```

✅ rollout 동안 `kubectl get events --watch`나 API 응답 지연을 느껴보세요. **객체 수보다 변경 빈도(churn)가 control plane을 두드린다**는 theory §2의 체감판. 실무에서 "전 서비스 동시 재배포"가 금기인 이유.

## Step 6. (선택) 노드 10,000개는?

```bash
# Step 2의 루프를 10000까지 늘려보세요 — 어느 시점부터
#  - kubectl get nodes가 눈에 띄게 느려지고 (LIST 비용)
#  - kind의 단일 etcd/API 서버(작은 컨테이너)가 헐떡입니다
# "control plane 사양이 노드 수의 천장"임을 로컬에서 안전하게 관찰할 수 있습니다
```

## 정리

```bash
bash cleanup.sh    # kind 클러스터 통째 삭제 (가짜 노드 1000개도 함께)
```
