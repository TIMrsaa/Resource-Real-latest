# Lab 01 — EKS 클러스터 생성 + 아키텍처 실체 확인

> **목표**: 공유 학습 클러스터를 만들고, theory.md의 그림 속 컴포넌트들을 실제로 찾아봅니다.
> **비용**: control plane $0.10/h + t3.medium Spot 2대 ≈ $0.13/h

## 사전 조건

```bash
aws --version        # v2.x
eksctl version       # 최신 (없으면: https://eksctl.io/installation/)
kubectl version --client   # 1.35~1.37 (서버 1.36과 ±1 마이너 이내)
aws sts get-caller-identity   # 자격증명 확인
```

## Step 1. 클러스터 생성 (~20분)

```bash
eksctl create cluster --name k8s-study --region ap-northeast-2 \
  --version 1.36 \
  --nodegroup-name workers --node-type t3.medium --nodes 2 \
  --spot --managed
```

예상 출력 (마지막 줄):
```
[✓]  EKS cluster "k8s-study" in "ap-northeast-2" region is ready
```

기다리는 동안: eksctl이 내부적으로 CloudFormation 스택 2개(클러스터/노드그룹)를 만듭니다. 콘솔 → CloudFormation에서 진행 상황을 구경하세요.

## Step 2. 접속 확인 — control plane은 URL입니다

```bash
kubectl get nodes -o wide
```

예상 출력:
```
NAME                            STATUS  ROLES   AGE  VERSION  ...
ip-192-168-xx-xx.ap-northeast-2.compute.internal  Ready  <none>  2m  v1.36.x
ip-192-168-yy-yy.ap-northeast-2.compute.internal  Ready  <none>  2m  v1.36.x
```

✅ **검증 포인트**: 노드가 2개뿐입니다. control plane 노드가 **없습니다** — AWS 소유라서 안 보입니다.

```bash
kubectl cluster-info
```

예상 출력:
```
Kubernetes control plane is running at https://XXXX.gr7.ap-northeast-2.eks.amazonaws.com
```

우리에게 control plane은 이 **HTTPS URL이 전부**입니다.

## Step 3. kubectl = HTTP 클라이언트임을 확인

```bash
kubectl get pods -v=8 2>&1 | grep -E "GET|Request"
```

예상 출력 (발췌):
```
GET https://XXXX.eks.amazonaws.com/api/v1/namespaces/default/pods?limit=500
```

✅ kubectl의 정체는 REST API 호출 도구입니다. `-v=8`은 디버깅 만능 옵션이니 기억해두라.

## Step 4. 그림 속 노드 컴포넌트 찾기

```bash
# kube-proxy와 CNI는 DaemonSet(노드마다 1개) Pod로 돕니다
kubectl get pods -n kube-system -o wide
```

예상 출력:
```
NAME                       READY   STATUS    ...   NODE
aws-node-xxxxx             2/2     Running   ...   ip-192-168-xx-xx...   ← VPC CNI
aws-node-yyyyy             2/2     Running   ...   ip-192-168-yy-yy...
coredns-xxxxxxxxxx-aaaaa   1/1     Running                               ← 클러스터 DNS
coredns-xxxxxxxxxx-bbbbb   1/1     Running
kube-proxy-xxxxx           1/1     Running   ...   ip-192-168-xx-xx...
kube-proxy-yyyyy           1/1     Running   ...   ip-192-168-yy-yy...
metrics-server-...         1/1     Running                               ← 1.36 기본 포함
```

✅ **검증 포인트**: kube-proxy/aws-node가 **노드 수만큼** 있습니다. kubelet은 왜 없을까요? — kubelet은 Pod가 아니라 노드 OS의 systemd 서비스입니다 (Pod를 만드는 주체가 Pod일 수는 없으니).

```bash
# kubelet의 실체 확인 (노드의 프로세스)
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl debug node/$NODE -it --image=busybox -- sh -c 'ps | grep kubelet | head -2'
```

예상 출력:
```
 2811 root   ... /usr/bin/kubelet --config=/etc/kubernetes/kubelet/config.json ...
```

## Step 5. API 리소스의 전경 훑기

```bash
kubectl api-resources | head -25
kubectl api-resources | wc -l
```

예상: 60개 이상의 리소스 종류. 이 목록이 앞으로 배울 것들의 전체 메뉴판입니다. 지금 다 몰라도 됩니다 — `SHORTNAMES` 열(po, svc, deploy...)만 눈에 익혀두자.

## Step 6. watch 메커니즘 직접 보기

터미널 2개를 열고:

```bash
# 터미널 1: watch 구독
kubectl get pods -w

# 터미널 2: Pod 생성
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: hello
  labels: { run: hello }
spec:
  containers:
    - name: hello
      image: public.ecr.aws/nginx/nginx:latest
EOF
```

터미널 1 예상 출력 (실시간으로 한 줄씩):
```
NAME    READY   STATUS              RESTARTS   AGE
hello   0/1     Pending             0          0s
hello   0/1     ContainerCreating   0          0s
hello   1/1     Running             0          4s
```

✅ **검증 포인트**: `Pending → ContainerCreating → Running` 전이가 실시간 스트림으로 옵니다. 스케줄러/kubelet도 정확히 이 watch로 일합니다. 각 단계가 누구의 작업인지는 lab-02에서 추적합니다.

## 트러블슈팅

| 증상 | 원인/해결 |
|------|----------|
| `Error: checking AWS STS access` | `aws configure` 자격증명/리전 확인 |
| 클러스터 생성 중 `Cannot create cluster ... UnsupportedAvailabilityZoneException` | `--zones ap-northeast-2a,ap-northeast-2c` 명시 |
| `kubectl: Unauthorized` | `aws eks update-kubeconfig --name k8s-study --region ap-northeast-2` |
| Spot 용량 부족으로 노드 안 뜸 | `--node-type t3a.medium` 등 다른 타입 재시도 |

## 정리

```bash
kubectl delete pod hello
# 클러스터는 삭제하지 말 것! 다음 모듈에서 계속 사용.
# 오늘 학습 끝이고 며칠 쉴 거라면:
# eksctl delete cluster --name k8s-study --region ap-northeast-2
```
