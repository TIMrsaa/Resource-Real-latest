# Lab 01 — Rollout 카나리: 단계별 트래픽과 수동 승격

Argo Rollouts를 설치하고, 11에서 replica로 흉내 낸 카나리를 **1급 기능**으로 구현합니다. 단계별 트래픽 전환과 수동 승격을 먼저 보고, lab-02에서 자동화합니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. Argo Rollouts 설치

```bash
kubectl create namespace argo-rollouts 2>/dev/null || true
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
kubectl -n argo-rollouts rollout status deploy/argo-rollouts --timeout=120s

# kubectl plugin (관찰용)
curl -sLO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64 2>/dev/null && \
  chmod +x kubectl-argo-rollouts-linux-amd64 && sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts 2>/dev/null || \
  echo "plugin 설치 권장"
```

## Step 2. Rollout — Deployment 대신

```bash
kubectl create ns pdlab
cat <<'EOF' | kubectl apply -n pdlab -f -
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata: { name: demo }
spec:
  replicas: 10
  selector: { matchLabels: { app: demo } }
  template:
    metadata: { labels: { app: demo } }
    spec:
      containers:
      - name: app
        image: ghcr.io/stefanprodan/podinfo:6.7.0    # 시작 버전
        ports: [{ containerPort: 9898 }]
        resources: { requests: { cpu: 50m, memory: 32Mi } }
  strategy:
    canary:                          # ★ 카나리 네이티브 (11의 replica 조작이 1급으로)
      steps:
        - setWeight: 10              # 10%
        - pause: { duration: 30s }
        - setWeight: 30
        - pause: {}                  # 무한 — 수동 승격 대기
        - setWeight: 60
        - pause: { duration: 30s }
        - setWeight: 100
---
apiVersion: v1
kind: Service
metadata: { name: demo, namespace: pdlab }
spec:
  selector: { app: demo }
  ports: [{ port: 80, targetPort: 9898 }]
EOF
kubectl argo rollouts -n pdlab get rollout demo 2>/dev/null || kubectl -n pdlab get rollout demo
```

예상: 10 replicas가 stable로 배포됨(첫 배포는 카나리 없이 전체).

## Step 3. 새 버전 배포 — 카나리 시작

```bash
kubectl argo rollouts -n pdlab set image demo app=ghcr.io/stefanprodan/podinfo:6.7.1 2>/dev/null || \
  kubectl -n pdlab patch rollout demo --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"ghcr.io/stefanprodan/podinfo:6.7.1"}]'

# 카나리 진행 관찰
for i in $(seq 1 8); do
  echo "=== $(date +%T) ==="
  kubectl -n pdlab get rollout demo -o jsonpath='{.status.phase} / canary weight: {.status.canary.weights.canary.weight}{"\n"}' 2>/dev/null
  kubectl -n pdlab get rs -l app=demo -o custom-columns='RS:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,READY:.status.readyReplicas' 2>/dev/null | grep -v "0$" | head
  sleep 20
done
```

예상: 카나리 ReplicaSet(6.7.1)이 생기고, 트래픽이 10% → 30%로 오르다가 **pause: {} 에서 멈춥니다**(무한 대기). ✅ 11의 replica 조작이 **단계별 자동 트래픽 전환**으로 — 1급 기능.

## Step 4. 트래픽 분포 확인

```bash
# 현재 카나리 weight에 맞춰 트래픽이 나뉘는가
kubectl run probe -n pdlab --rm -i --restart=Never --image=curlimages/curl -- sh -c \
  'for i in $(seq 1 30); do curl -s http://demo/ | grep -o "6\.7\.[01]"; done | sort | uniq -c'
```

예상: 6.7.0(stable)과 6.7.1(canary)이 현재 weight 비율로. (Service 기반이라 replica 비율 근사 — 정밀 %는 트래픽 제공자 필요, theory §4)

## Step 5. 수동 승격 (01의 배포 버튼)

`pause: {}`는 사람의 판단을 기다립니다 — 01의 Continuous Delivery:

```bash
echo "카나리 30%에서 대기 중 — 사람이 지표를 보고 판단 (lab-02에서 자동화)"
kubectl argo rollouts -n pdlab promote demo 2>/dev/null || \
  kubectl -n pdlab patch rollout demo --type=merge -p '{"status":{"pauseConditions":null}}' 2>/dev/null || \
  echo "promote 명령 (plugin 필요)"

sleep 40
kubectl -n pdlab get rollout demo -o jsonpath='{.status.phase} / {.status.canary.weights.canary.weight}{"\n"}' 2>/dev/null
```

✅ 승격하니 60% → 100%로 진행. **수동 승격 = 11의 사람 판단**. lab-02에서 이 판단을 메트릭 자동 분석으로 대체합니다.

## Step 6. 롤백도 즉시 (11의 롤백 속도)

```bash
# 나쁜 버전을 배포했다면 abort로 즉시 stable 복귀
kubectl argo rollouts -n pdlab set image demo app=ghcr.io/stefanprodan/podinfo:bad-tag 2>/dev/null || true
sleep 20
kubectl argo rollouts -n pdlab abort demo 2>/dev/null || \
  echo "abort = 카나리 폐기, stable 100% 복귀 (11의 가중치 0 = 초 단위)"
sleep 15
kubectl -n pdlab get rollout demo -o jsonpath='{.status.phase}{"\n"}'
```

✅ abort는 트래픽을 stable로 즉시 복귀 — 11의 "카나리 롤백은 초 단위"(구버전이 살아 있으니). lab-02에서 이 abort가 **자동**이 됩니다.

## Step 7. 산출물

```markdown
# Rollout 카나리 (수동) — 11 대비
| | 11(수동 replica) | 17 Rollout(수동 승격) |
|---|---|---|
| 트래픽 전환 | 손으로 scale | 단계별 자동(setWeight) |
| 정밀도 | replica 비율(조잡) | weight(+트래픽 제공자면 정밀) |
| 승격 판단 | 사람 | 사람(pause) → lab-02에서 자동 |
| 롤백 | 손으로 scale 0 | abort(초 단위) → lab-02 자동 |
→ 아직 "사람이 지표 보고 판단" — lab-02가 그것을 코드화
```

## 정리

demo Rollout은 lab-02에서 자동 분석에 사용.
