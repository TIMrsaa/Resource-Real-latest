# Lab 01 — 프로파일 만들고 캡슐호텔 체크인

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. Fargate 프로파일 생성

```bash
kubectl create ns serverless
eksctl create fargateprofile --cluster $CLUSTER --region $AWS_REGION \
  --name fp-serverless --namespace serverless
# 확인 (생성 ~2분)
aws eks describe-fargate-profile --cluster-name $CLUSTER --region $AWS_REGION \
  --fargate-profile-name fp-serverless \
  --query 'fargateProfile.{status:status,selectors:selectors,podRole:podExecutionRoleArn}'
```

✅ `podExecutionRoleArn` — Fargate VM이 이미지 풀/로그 전송에 쓰는 역할(eksctl이 생성). selectors의 `namespace: serverless`가 "이 ns의 Pod는 Fargate로"의 규칙.

## Step 2. 배포 — 그리고 가상 노드의 출현

터미널 1: `kubectl get nodes -w`
터미널 2:
```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: capsule
  namespace: serverless
  labels: { app: capsule }
spec:
  replicas: 2
  selector:
    matchLabels: { app: capsule }
  template:
    metadata:
      labels: { app: capsule }
    spec:
      containers:
        - name: nginx
          image: public.ecr.aws/nginx/nginx:1.27
EOF
kubectl get pods -n serverless -w    # Pending이 평소보다 깁니다 (~1분: VM 프로비저닝!)
```

터미널 1 예상:
```
fargate-ip-192-168-x-x...   Ready    ← Pod당 하나씩, 2개 출현!
```

✅ **Pod 2개 = "노드" 2개** — 캡슐호텔의 실물. 시작 지연(수십 초)도 직접 체감했습니다 (VM 기동 + 이미지 풀 매번 — 캐시 없음).

## Step 3. 가상 노드 해부

```bash
kubectl get nodes -o wide | grep fargate
FNODE=$(kubectl get pods -n serverless -o jsonpath='{.items[0].spec.nodeName}')
kubectl describe node $FNODE | grep -E "capacity|allocatable|Taints|eks.amazonaws.com" -A2 | head -12
kubectl get pods -A --field-selector spec.nodeName=$FNODE    # 그 Pod 하나뿐!
```

✅ 확인 포인트: ① 노드에 Pod가 **딱 하나**(+있어도 같은 Pod의 것) ② `eks.amazonaws.com/compute-type=fargate` 라벨/taint ③ capacity가 Pod 요청에 맞춘 슬롯 크기.

## Step 4. 스케줄러 바꿔치기의 증거 (k8s 23/25 연결)

```bash
kubectl get pod -n serverless -o jsonpath='{.items[0].spec.schedulerName}'; echo
# → fargate-scheduler   (내가 지정한 적 없습니다!)
```

✅ EKS의 mutating webhook이 프로파일 매칭 Pod의 schedulerName을 바꿨습니다 — k8s 23(웹훅)과 25(멀티 스케줄러)가 관리형 서비스 안에서 일하는 현장.

## Step 5. 반올림의 경제학 실측

```bash
# 0.3 vCPU / 600Mi 요청 → 어느 슬롯?
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: sizer
  namespace: serverless
  labels: { run: sizer }
spec:
  containers:
    - name: sizer
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
      resources:
        requests: { cpu: 300m, memory: 600Mi }
EOF
kubectl wait --for=condition=Ready pod/sizer -n serverless --timeout=180s
kubectl get pod sizer -n serverless \
  -o jsonpath='{.metadata.annotations.CapacityProvisioned}'; echo
```

예상: `0.5vCPU 1GB` 류 — 요청(0.3/600Mi)보다 **큰 규격 슬롯**.

✅ annotation `CapacityProvisioned` = 실제 청구 단위. 0.3을 요청해도 0.5 요금 — requests 설계(k8s 09)가 Fargate에선 곧장 돈입니다. 우리 Pod의 요청을 슬롯 규격에 맞추는 것(예: 0.25/0.5/1 vCPU 경계)이 Fargate 비용 최적화의 1번.

## Step 6. 로그 — 노드 에이전트 없이

```bash
# Fargate 내장 로그 라우터(Fluent Bit) 설정: aws-observability ns의 ConfigMap
kubectl create ns aws-observability 2>/dev/null || true
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata: { name: aws-logging, namespace: aws-observability }
data:
  flb_log_cw: "false"
  output.conf: |
    [OUTPUT]
        Name cloudwatch_logs
        Match *
        region ap-northeast-2
        log_group_name /eks/k8s-study/fargate
        auto_create_group true
EOF
```

✅ DaemonSet 로그 수집기(12에서 표준 방식)가 불가능하니, **플랫폼 내장 라우터를 ConfigMap으로 설정**하는 것이 Fargate의 로깅 — "노드 없음"이 바꾸는 운영 방식의 예. (실제 전송은 pod execution role에 CloudWatch 권한 필요 — 개념 확인까지)

## 정리

리소스는 lab-02에서 계속 사용.
