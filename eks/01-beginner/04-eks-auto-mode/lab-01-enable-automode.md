# Lab 01 — Auto Mode 켜고, 띄우고, 노드의 출생 관찰

> ⚠️ 비용: Auto Mode 노드는 EC2 + 관리 수수료. lab 끝나면 워크로드를 지워 노드가 0으로 회수되는 것까지 확인합니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. 기존 클러스터에 Auto Mode 활성화

```bash
# 노드 역할 (Auto Mode 노드용 — 없으면 생성. eksctl 사용 시 자동)
aws eks update-cluster-config --name $CLUSTER --region $AWS_REGION \
  --compute-config '{"enabled":true,"nodePools":["general-purpose","system"]}' \
  --kubernetes-network-config '{"elasticLoadBalancing":{"enabled":true}}' \
  --storage-config '{"blockStorage":{"enabled":true}}'
# 적용 대기 (수 분)
aws eks describe-cluster --name $CLUSTER --region $AWS_REGION \
  --query 'cluster.computeConfig'
```

> 실패 시(역할/버전 요건): 에러 메시지의 요구사항을 따라가거나, eksctl로: `eksctl utils update-cluster-config ... --enable-auto-mode` 계열 명령 확인. (기능이 진화 중이니 공식 문서 절차 우선)

```bash
kubectl get nodepools    # general-purpose, system 이 보이면 성공
```

✅ **클러스터에 Karpenter를 설치한 적이 없는데 NodePool API가 있습니다** — 내장 컨트롤러가 control plane 쪽에서 돌고 있다는 증거 (경계선 너머로 들어간 Karpenter).

## Step 2. 표준 노드와 Auto Mode 노드의 공존 확인

```bash
kubectl get nodes -L eks.amazonaws.com/compute-type
# 기존 관리형 노드그룹 노드들만 보입니다 (Auto Mode 노드는 아직 0 — 수요가 없으니까!)
```

✅ Karpenter 계열의 핵심 철학 선체험: **노드는 미리 있지 않고, Pod가 요구할 때 태어납니다.**

## Step 3. Auto Mode 노드의 출생 — 수요 만들기

```bash
# Auto Mode 풀로만 가도록 nodeSelector 지정
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: auto-test }
spec:
  replicas: 2
  selector: { matchLabels: { app: auto-test } }
  template:
    metadata: { labels: { app: auto-test } }
    spec:
      nodeSelector: { eks.amazonaws.com/compute-type: auto }
      containers:
      - name: web
        image: public.ecr.aws/nginx/nginx:1.27
        resources: { requests: { cpu: 500m, memory: 512Mi } }
EOF

# 관찰 (2개 터미널 추천)
kubectl get pods -l app=auto-test -w          # Pending → ... → Running
kubectl get nodes -L eks.amazonaws.com/compute-type -w    # 새 노드 출현!
```

예상 타임라인: Pending(스케줄 불가 — 맞는 노드 없음) → 내장 Karpenter가 인스턴스 기동(~1분대) → 노드 Ready → Pod Running.

✅ k8s 12에서 배운 "Pending = 스케줄러의 거절"이 여기선 **노드 탄생의 신호**가 됩니다. 이벤트로 확인:

```bash
kubectl get events --sort-by=.lastTimestamp | grep -i -E "nodeclaim|launched|provisioned" | tail -3
```

## Step 4. 태어난 노드 관찰 — 다른 종족입니다

```bash
NODE=$(kubectl get pods -l app=auto-test -o jsonpath='{.items[0].spec.nodeName}')
kubectl describe node $NODE | grep -E "eks.amazonaws.com/compute-type|os-image|kubelet" | head -4
kubectl get pods -A --field-selector spec.nodeName=$NODE
```

✅ 확인 포인트: ① OS가 Bottlerocket ② **그 노드에 aws-node(VPC CNI)·kube-proxy Pod가 없습니다** — 내장 프로세스로 돌기 때문(theory §1). 표준 노드와 나란히 두고 보면 차이가 선명합니다:

```bash
kubectl get pods -n kube-system -o wide | grep -E "aws-node|kube-proxy" | head -5
# → 표준 노드들에만 떠 있습니다
```

## Step 5. 노드의 죽음 — 수요가 사라지면

```bash
kubectl delete deployment auto-test
kubectl get nodes -w    # 수 분 내 Auto Mode 노드가 사라집니다 (consolidation: 빈 노드 회수)
```

✅ **수요 종료 = 노드 소멸 = 과금 종료.** 표준 노드그룹(desired 고정)과의 결정적 차이 — "노드를 빌려 쓰는" 모델의 실감. 이것이 eks 22(비용)의 핵심 레버 중 하나입니다.

## 정리

Auto Mode 자체는 켜둡니다(lab-02에서 사용). 워크로드가 없으면 Auto Mode 노드 비용은 0.
