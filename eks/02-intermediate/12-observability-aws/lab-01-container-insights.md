# Lab 01 — Container Insights 켜기: 애드온 하나, 파이프라인 전부

11의 애드온 절차를 그대로 재사용해 관측성 스택을 깔고, theory §3~4의 "로그의 길·메트릭의 길"을 양끝에서 확인합니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

## Step 1. 권한 — agent가 CloudWatch에 쓸 자격 (09의 배선)

cloudwatch-agent SA에 Pod Identity로 AWS 관리형 정책을 연결합니다:

```bash
# Pod Identity용 역할 (신뢰 주체: pods.eks.amazonaws.com — 09에서 본 형태)
cat > cw-trust.json <<'EOF'
{ "Version": "2012-10-17", "Statement": [{
  "Effect": "Allow",
  "Principal": { "Service": "pods.eks.amazonaws.com" },
  "Action": ["sts:AssumeRole","sts:TagSession"] }]}
EOF
aws iam create-role --role-name CWObservabilityLab \
  --assume-role-policy-document file://cw-trust.json 2>/dev/null || true
aws iam attach-role-policy --role-name CWObservabilityLab \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
```

## Step 2. 애드온 설치 — 11의 절차 그대로

```bash
# 현 CP 버전의 default 버전 확인 (latest 아님 — 11의 규칙)
aws eks describe-addon-versions --addon-name amazon-cloudwatch-observability \
  --kubernetes-version 1.36 --region $AWS_REGION \
  --query 'addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion' --output text

aws eks create-addon --cluster-name $CLUSTER --region $AWS_REGION \
  --addon-name amazon-cloudwatch-observability \
  --pod-identity-associations serviceAccount=cloudwatch-agent,roleArn=arn:aws:iam::$ACCOUNT_ID:role/CWObservabilityLab

# ACTIVE까지 감시 (1~2분)
watch -n5 "aws eks describe-addon --cluster-name $CLUSTER --region $AWS_REGION \
  --addon-name amazon-cloudwatch-observability --query 'addon.status' --output text"
```

## Step 3. 무엇이 깔렸나 — theory §2의 지도 대조

```bash
kubectl get pods -n amazon-cloudwatch -o wide
kubectl get ds,deploy -n amazon-cloudwatch
```

예상: Operator(Deployment) + **cloudwatch-agent DaemonSet** + **fluent-bit DaemonSet** — 노드 수만큼의 agent/fluent-bit Pod. ✅ "로그 수집은 노드 단위"(k8s 13의 DaemonSet이 정확히 이 일을 위해 존재)를 실물로 확인.

```bash
# fluent-bit이 실제로 노드 로그 파일을 보고 있는지 (theory §3의 경로)
kubectl exec -n amazon-cloudwatch ds/fluent-bit -- ls /var/log/containers | head -5
```

## Step 4. 로그의 길 — 말하는 워크로드로 검증

```bash
kubectl create ns obs
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: chatterbox
  namespace: obs
  labels: { app: chatterbox }
spec:
  replicas: 1
  selector:
    matchLabels: { app: chatterbox }
  template:
    metadata:
      labels: { app: chatterbox }
    spec:
      containers:
        - name: chatterbox
          image: public.ecr.aws/docker/library/busybox:stable
          command: ["sh", "-c", 'while true; do echo "hello from chatterbox rps=$((RANDOM%100))"; sleep 2; done']
EOF
kubectl rollout status deploy/chatterbox -n obs

# 1~2분 후 — 로그 그룹 4형제가 생겼는지
aws logs describe-log-groups --log-group-name-prefix /aws/containerinsights/$CLUSTER \
  --region $AWS_REGION --query 'logGroups[].logGroupName'

# stdout 한 줄이 CloudWatch에 도착했는지 (tail로 실시간 확인)
aws logs tail /aws/containerinsights/$CLUSTER/application --region $AWS_REGION \
  --since 2m --filter-pattern chatterbox | head -5
```

예상: `hello from chatterbox ...` 줄들이 **kubernetes 메타데이터(ns/pod 이름)가 붙은 JSON**으로 도착. ✅ stdout → 노드 파일 → Fluent Bit → CloudWatch — 전 구간 개통. Pod를 지워도 이 로그는 남습니다(38의 `logs --previous`가 못 하던 것).

## Step 5. 메트릭의 길 — EMF의 반전 확인

```bash
# ContainerInsights 메트릭이 서기 시작했는지 (5분쯤 걸림)
aws cloudwatch list-metrics --namespace ContainerInsights --region $AWS_REGION \
  --query 'Metrics[].MetricName' --output text | tr '\t' '\n' | sort -u | head -12

# 그 메트릭의 원료 — /performance 로그 그룹의 EMF JSON
aws logs tail /aws/containerinsights/$CLUSTER/performance --region $AWS_REGION --since 2m | head -3
```

예상: `pod_cpu_utilization`, `node_memory_utilization` 등 + performance 로그에 `"CloudWatchMetrics":[...]`가 박힌 JSON. ✅ **메트릭이 로그(EMF)로 들어와 메트릭이 됩니다** — "메트릭 안 보임" 디버깅이 왜 /performance에서 끝나는지의 물증.

## Step 6. 콘솔 한 바퀴 (눈으로 굳히기)

CloudWatch 콘솔 → Insights → **Container Insights**: 클러스터/노드/Pod 계층의 CPU·메모리·네트워크·재시작 대시보드가 이미 그려져 있습니다. eks 03에서 "노드 헬스를 어디서 보나", 04에서 "노드 접근이 없는데 어떻게 아나"의 답이 이 화면입니다.

## 정리

obs ns와 애드온은 lab-02의 재료 — 유지. (수집이 시작됐다 = **과금이 시작됐습니다.** lab-02에서 통제를 배우고 cleanup까지 반드시.)
