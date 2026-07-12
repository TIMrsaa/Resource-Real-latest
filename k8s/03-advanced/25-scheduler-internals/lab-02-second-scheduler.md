# Lab 02 — 두 번째 스케줄러 배포 (bin-packing 성향)

> EKS의 기본 스케줄러는 못 건드리지만, **스케줄러를 Pod로 하나 더** 띄우는 것은 자유입니다. MostAllocated(bin-packing) 성향의 "cost-scheduler"를 배포합니다.

## Step 1. 설정과 RBAC

```bash
kubectl create ns scheduler-lab

# KubeSchedulerConfiguration (bin-packing + 자체 이름)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata: { name: cost-scheduler-config, namespace: scheduler-lab }
data:
  config.yaml: |
    apiVersion: kubescheduler.config.k8s.io/v1
    kind: KubeSchedulerConfiguration
    leaderElection:
      leaderElect: false
    profiles:
    - schedulerName: cost-scheduler
      pluginConfig:
      - name: NodeResourcesFit
        args:
          scoringStrategy:
            type: MostAllocated          # ★ 꽉 채우기
            resources: [{ name: cpu, weight: 1 }, { name: memory, weight: 1 }]
EOF

# 스케줄러는 많은 읽기 + binding 쓰기 권한이 필요 — 학습 단순화로 내장 ClusterRole 활용
kubectl create serviceaccount cost-scheduler -n scheduler-lab
kubectl create clusterrolebinding cost-scheduler-as-kube-scheduler \
  --clusterrole=system:kube-scheduler --serviceaccount=scheduler-lab:cost-scheduler
kubectl create clusterrolebinding cost-scheduler-as-volume-scheduler \
  --clusterrole=system:volume-scheduler --serviceaccount=scheduler-lab:cost-scheduler
# 엔드포인트/리스 등 부족분 (버전에 따라): events 기록 권한
kubectl create clusterrolebinding cost-scheduler-extra \
  --clusterrole=edit --serviceaccount=scheduler-lab:cost-scheduler
```

## Step 2. 스케줄러 Deployment

```bash
# 클러스터와 같은 마이너 버전의 kube-scheduler 이미지 사용
VER=$(kubectl version -o json | python3 -c "import json,sys;print(json.load(sys.stdin)['serverVersion']['gitVersion'].split('-')[0])")
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: cost-scheduler, namespace: scheduler-lab }
spec:
  replicas: 1
  selector: { matchLabels: { app: cost-scheduler } }
  template:
    metadata: { labels: { app: cost-scheduler } }
    spec:
      serviceAccountName: cost-scheduler
      volumes:
      - { name: config, configMap: { name: cost-scheduler-config } }
      containers:
      - name: scheduler
        image: registry.k8s.io/kube-scheduler:$VER
        command: ["kube-scheduler", "--config=/etc/kubernetes/config.yaml", "-v=2"]
        volumeMounts: [{ name: config, mountPath: /etc/kubernetes }]
        resources: { requests: { cpu: 50m, memory: 64Mi } }
EOF
kubectl rollout status deploy/cost-scheduler -n scheduler-lab
kubectl logs -n scheduler-lab deploy/cost-scheduler --tail=5
```

예상 로그: 캐시 동기화/프로파일 로딩 후 대기 상태.

## Step 3. schedulerName으로 분기 검증

```bash
# 기본 스케줄러용과 cost-scheduler용 Pod를 나란히
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: by-default
  labels: { run: by-default }
spec:
  containers:
    - name: by-default
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "300"]
---
apiVersion: v1
kind: Pod
metadata:
  name: by-cost
  labels: { run: by-cost }
spec:
  schedulerName: cost-scheduler        # ← 이 한 줄이 담당 스케줄러를 바꿉니다
  containers:
    - name: by-cost
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "300"]
EOF
sleep 8
kubectl get events --field-selector reason=Scheduled \
  -o custom-columns=POD:.involvedObject.name,BY:.reportedBy,SRC:.source.component | grep -E "by-"
```

예상 출력:
```
by-default   ...   default-scheduler
by-cost      ...   cost-scheduler        ← 내가 띄운 스케줄러가 배치했습니다!
```

✅ **스케줄러가 둘이 공존**하고, Pod가 spec.schedulerName으로 선택합니다. (서로 다른 Pod를 다루므로 충돌하지 않습니다 — 같은 Pod를 두 스케줄러가 보게 만드는 것이 진짜 사고)

## Step 4. 성향 차이 관찰 — 채우기 vs 퍼뜨리기

```bash
# 같은 크기 Pod 6개를 각 스케줄러로 배치해 분포 비교
for i in 1 2 3; do
  kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: spread-$i
  labels: { run: spread-$i }
spec:
  containers:
    - name: c
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "300"]
      resources:
        requests: { cpu: 200m }
---
apiVersion: v1
kind: Pod
metadata:
  name: pack-$i
  labels: { run: pack-$i }
spec:
  schedulerName: cost-scheduler
  containers:
    - name: c
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "300"]
      resources:
        requests: { cpu: 200m }
EOF
done
sleep 10
echo "=== default (spreading) ==="; kubectl get pods -o wide | grep spread- | awk '{print $7}' | sort | uniq -c
echo "=== cost (bin-packing) ===";  kubectl get pods -o wide | grep pack-   | awk '{print $7}' | sort | uniq -c
```

예상 (노드 2대, 기존 부하에 따라 다를 수 있음):
```
=== default (spreading) ===
   2 ip-...aaa     ← 고르게
   1 ip-...bbb
=== cost (bin-packing) ===
   3 ip-...aaa     ← 한 노드에 몰아넣음!
```

✅ 같은 클러스터, 같은 Pod인데 **점수 전략 하나로 분포가 달라집니다.** bin-packing은 빈 노드를 만들어 회수(비용 절감)를 가능케 하지만, 노드 장애 폭발 반경은 커집니다 — spreading과의 트레이드오프를 눈으로 확인.

## 정리

```bash
bash cleanup.sh
```
