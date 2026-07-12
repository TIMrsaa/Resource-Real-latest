# Lab 01 — 3층 해부와 용도별 풀 추가

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. 기존 노드그룹의 3층 내려가기

```bash
NG=$(aws eks list-nodegroups --cluster-name $CLUSTER --region $AWS_REGION --query 'nodegroups[0]' --output text)

# 1층: EKS Nodegroup (정책)
aws eks describe-nodegroup --cluster-name $CLUSTER --nodegroup-name $NG --region $AWS_REGION \
  --query 'nodegroup.{ami:amiType,types:instanceTypes,scaling:scalingConfig,update:updateConfig,health:health.issues}'

# 2층: ASG (집행자)
ASG=$(aws eks describe-nodegroup --cluster-name $CLUSTER --nodegroup-name $NG --region $AWS_REGION \
  --query 'nodegroup.resources.autoScalingGroups[0].name' --output text)
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG --region $AWS_REGION \
  --query 'AutoScalingGroups[0].{min:MinSize,max:MaxSize,desired:DesiredCapacity,azs:AvailabilityZones}'
# ASG의 활동 이력 — "노드가 안 늘어요"의 진단처!
aws autoscaling describe-scaling-activities --auto-scaling-group-name $ASG --region $AWS_REGION \
  --query 'Activities[0:3].{status:StatusCode,cause:Cause}' --output table

# 3층: EC2 (실물)
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG --region $AWS_REGION \
  --query 'AutoScalingGroups[0].Instances[].{id:InstanceId,az:AvailabilityZone,health:HealthStatus}' --output table
```

✅ **같은 사실의 세 시점**: EKS는 "정책 2대", ASG는 "유지 활동 이력", EC2는 "실제 머신". 노드 문제의 진단은 이 사다리를 내려가는 것입니다.

## Step 2. 3층의 연결 체험 — EC2를 직접 죽이면

```bash
VICTIM=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $ASG --region $AWS_REGION \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)
kubectl get nodes    # 현재 노드 기억
aws ec2 terminate-instances --instance-ids $VICTIM --region $AWS_REGION
# 관찰 (수 분)
kubectl get nodes -w    # 하나 사라지고 → 새 노드 합류
```

✅ ASG가 결원을 감지하고 **자동 충원** — 모듈 01에서 말한 "회색지대"(소유는 나, 수명주기는 AWS 도구)의 실연. 그 노드에 있던 Pod들은? ReplicaSet이 다른 노드에 재생성(k8s 04) — **인프라 자동 복구와 워크로드 자동 복구의 합주**입니다. (단, drain 없는 급사라 PDB는 못 지켜줬습니다 — 계획 교체와 장애 교체의 차이)

## Step 3. 용도별 풀 추가 — Spot 배치 풀

```bash
cat > batch-pool.yaml <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata: { name: $CLUSTER, region: $AWS_REGION }
managedNodeGroups:
- name: spot-batch
  instanceTypes: [t3.large, t3a.large, m5.large]   # 다양화 (theory §3)
  spot: true
  desiredCapacity: 1
  minSize: 0
  maxSize: 2
  labels: { pool: spot-batch }
  taints: [{ key: pool, value: spot-batch, effect: NoSchedule }]
EOF
eksctl create nodegroup -f batch-pool.yaml    # ~수 분 (CFN 스택 하나 추가)
kubectl get nodes -L pool,eks.amazonaws.com/capacityType
```

✅ 새 노드에 `capacityType=SPOT` 라벨 — 그리고 taint 덕에 **일반 Pod는 안 들어갑니다**:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: normal
  labels: { run: normal }
spec:
  containers:
    - name: normal
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "300"]
EOF
kubectl get pod normal -o wide    # 일반 풀에 배치 (spot 노드 회피 확인)
```

## Step 4. 그 풀 전용 워크로드 — k8s 12 문법의 실전

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata: { name: spot-job }
spec:
  parallelism: 2
  completions: 4
  template:
    spec:
      restartPolicy: Never
      nodeSelector: { pool: spot-batch }
      tolerations: [{ key: pool, value: spot-batch, effect: NoSchedule }]
      containers:
      - name: work
        image: public.ecr.aws/docker/library/busybox:stable
        command: [sh, -c, 'echo crunching on $(hostname); sleep 20']
        resources: { requests: { cpu: 250m, memory: 128Mi } }
EOF
kubectl get pods -l job-name=spot-job -o wide -w    # 전부 spot 노드에!
```

✅ **"중단돼도 되는 일(Job — k8s 20)을 싼 자원(Spot)에"** — 비용 설계(22)의 기본 패턴 완성. Spot 중단이 와도 Job의 재시도(backoffLimit)가 받아줍니다 — 멱등성(k8s 20)이 전제인 이유.

## Step 5. 풀 설계 결정표 (산출물)

```markdown
# 우리 클러스터 풀 설계 (현재)
| 풀 | 타입 | capacity | taint | 입주 대상 |
|----|------|----------|-------|----------|
| workers(기존) | t3.medium | on-demand | 없음 | 일반/시스템 |
| spot-batch | t3/t3a/m5.large | spot | pool=spot-batch | Job/내결함 워커 |
| (미래) memory | r계열 | on-demand | pool=memory | 캐시/JVM |
판단 기준: 새 워크로드가 오면 ① 중단 허용? → spot ② 특수 자원? → 전용 풀 ③ 아니면 general
```

## 정리

spot-batch 풀은 lab-02에서 계속 사용. Job만 정리:
```bash
kubectl delete job spot-job; kubectl delete pod normal --ignore-not-found
```
