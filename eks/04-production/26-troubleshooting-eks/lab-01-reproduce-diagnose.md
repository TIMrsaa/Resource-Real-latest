# Lab 01 — 장애 3종을 만들고, 카드로 잡습니다

진단 카드가 실제로 작동하는지 검증합니다. 각 시나리오에서 **증상만 보고 계층을 판정**한 뒤 확진 명령을 실행하세요 — 답을 미리 읽지 말고.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
kubectl create ns tslab
```

## 시나리오 A — "Pod가 안 뜬다" (카드 3: IRSA 실패)

### 재현

```bash
# SA는 만들지만 IAM association은 일부러 빠뜨립니다
kubectl create serviceaccount broken-sa -n tslab
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: s3-reader, namespace: tslab }
spec:
  serviceAccountName: broken-sa
  containers:
  - name: cli
    image: public.ecr.aws/aws-cli/aws-cli:latest
    command: [sh, -c, "aws s3 ls; sleep 300"]
EOF
sleep 20
kubectl logs s3-reader -n tslab | head -3
```

증상: `Unable to locate credentials` — Pod는 **Running인데** AWS 호출만 실패.

### 진단 (카드 3의 확진 3단)

```bash
# ① 자격증명 주입 흔적이 있는가
kubectl exec -n tslab s3-reader -- env | grep AWS_ || echo "AWS_* 환경변수 없음 → 주입 자체가 안 됨"

# ② association이 존재하는가 (EKS 관리면)
eksctl get podidentityassociation --cluster $CLUSTER --region $AWS_REGION --namespace tslab 2>/dev/null || echo "association 없음"

# ③ (있다면) 신뢰 정책과 정책 범위 — 09의 3단
```

✅ 계층 판정 연습: 증상은 앱 로그(④)였지만 원인은 **EKS 관리면/IAM**(②①)이었습니다. `env`에 `AWS_ROLE_ARN`/토큰 경로가 없으면 "권한 부족"이 아니라 **배선 자체가 없는 것** — 정책을 뒤지기 전에 이걸 먼저 봅니다.

```bash
kubectl delete pod s3-reader -n tslab
```

## 시나리오 B — "새 Pod만 안 뜬다" (카드 1: IP 압박 모형)

진짜 서브넷을 고갈시킬 순 없으니(공유 클러스터!), **노드의 IP 예산을 소진**시켜 같은 증상을 만듭니다:

### 재현

```bash
# 노드 하나의 max-pods 근처까지 Pod를 채웁니다
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
MAXPODS=$(kubectl get node $NODE -o jsonpath='{.status.allocatable.pods}')
CUR=$(kubectl get pods -A --field-selector spec.nodeName=$NODE --no-headers | wc -l)
echo "노드 $NODE: $CUR / $MAXPODS"

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: filler
  namespace: tslab
  labels: { app: filler }
spec:
  replicas: $((MAXPODS - CUR + 3))         # maxPods를 넘기는 수 — IP 고갈 재현
  selector:
    matchLabels: { app: filler }
  template:
    metadata:
      labels: { app: filler }
    spec:
      nodeName: $NODE                      # 관찰 대상 노드에 몰아넣기
      containers:
        - name: pause
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.10
EOF
sleep 20
kubectl get pods -n tslab | grep -c Pending
```

### 진단

```bash
# 카드 1·2의 갈림길: 이벤트가 무엇을 말하나
PENDING=$(kubectl get pods -n tslab --field-selector status.phase=Pending -o name | head -1)
kubectl describe $PENDING -n tslab | grep -A3 Events | tail -3
```

- `Insufficient pods` / `Too many pods` → **노드의 Pod 슬롯**(max-pods — VPC CNI의 IP 회계, 07) 소진 = 카드 2
- 실제 서브넷 고갈이라면 → Pod는 스케줄되지만 `ContainerCreating`에서 멈추고 `failed to assign an IP address` = 카드 1

```bash
# 진짜 IP 예산 확인 (카드 1의 확진 — 16 lab-01의 그 명령)
SUBNETS=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION --query 'cluster.resourcesVpcConfig.subnetIds' --output text)
aws ec2 describe-subnets --subnet-ids $SUBNETS --region $AWS_REGION \
  --query 'Subnets[].{az:AvailabilityZone,free:AvailableIpAddressCount}' --output table
```

✅ **두 증상의 구분**이 이 시나리오의 핵심: "스케줄이 안 됨"(Pending, 슬롯 문제)과 "스케줄됐는데 IP를 못 받음"(ContainerCreating, 서브넷 문제)은 **다른 계층**입니다.

```bash
kubectl delete deploy filler -n tslab
```

## 시나리오 C — "유저만 502를 본다" (카드 4)

### 재현 (14의 대조군 재연 — 축약)

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: tslab
  labels: { app: web }
spec:
  replicas: 2
  selector:
    matchLabels: { app: web }
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
        - name: podinfo
          image: ghcr.io/stefanprodan/podinfo:6.7.1
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: tslab
spec:
  selector: { app: web }
  ports:
    - port: 9898
EOF
kubectl rollout status deploy/web -n tslab

# 앱은 완벽히 건강합니다
kubectl get endpoints web -n tslab
kubectl run probe -n tslab --rm -i --restart=Never --image=curlimages/curl -- \
  -s -o /dev/null -w "클러스터 내부: %{http_code}\n" http://web:9898/
```

내부는 200. 그런데 유저가 502를 본다면? (ALB가 있다면 14 lab-02를 재연)

### 진단 순서 (카드 4)

```markdown
1. 계층 판정: 앱 로그에 5xx 없음 + 엔드포인트 정상 → **ALB↔Pod 경계**(①/②)
2. 확진: ALB access log에서 elb_status_code=502, target_status_code=- (타깃이 답을 못 줌)
   → 502의 두 원인: keep-alive 역전 / draining 중 전송
3. 시각 상관: 502가 배포 시각에 몰리는가요? → 후자(preStop·readiness gate 부재)
                항상 산발적인가요? → 전자(앱 keep-alive < ALB idle 60s)
4. 처방: 14의 무중단 4종 세트 / 앱 keep-alive 75s
```

✅ 핵심 훈련: **"엔드포인트는 정상"이 앱의 알리바이이자 경계의 유죄 증거**입니다. 여기서 앱 코드를 뒤지면 하루를 잃습니다.

## 정리

```bash
kubectl delete ns tslab --ignore-not-found
```
