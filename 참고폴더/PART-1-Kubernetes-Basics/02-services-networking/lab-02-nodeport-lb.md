# Lab 02 — NodePort, LoadBalancer

## ⚠️ 비용 주의

이 lab의 LoadBalancer는 **AWS NLB를 실제로 만듭니다**. 끝나면 반드시 cleanup.
- NLB 시간당: 약 0.0225 USD
- 1시간 실습: 약 0.05 USD

## 학습 확인 포인트

- [ ] NodePort로 노드 IP에서 직접 접근해봤다
- [ ] LoadBalancer 가 자동으로 NLB를 만드는 걸 봤다
- [ ] LB DNS로 외부에서 접근해봤다

> **🌱 핵심 개념 미리보기**
> - **NodePort**: 모든 노드의 같은 포트(30000~32767)로 외부 노출. ClusterIP 위에 얹는 구조.
> - **LoadBalancer**: 클라우드의 실제 LB(AWS NLB/ELB)를 자동 생성. NodePort + ClusterIP를 포함함.
> - **Cloud Controller Manager**: K8s가 LoadBalancer Service 만들면 AWS API 호출해 NLB 만들어주는 컴포넌트.
> - **EXTERNAL-IP**: LoadBalancer 만들면 채워지는 LB의 DNS/IP. `<pending>` 이면 LB 생성 중.
> - **NLB의 Target Group**: NLB → Node 의 NodePort 로 트래픽 전달. health check 필수.

## 1. NodePort 배포 (web Deployment 가 lab-01에서 떠 있다고 가정)

```bash
kubectl apply -f manifests/nodeport.yaml
kubectl get svc web-nodeport
```

기대:
```
NAME           TYPE       CLUSTER-IP       EXTERNAL-IP   PORT(S)        AGE
web-nodeport   NodePort   10.100.234.56    <none>        80:30080/TCP   10s
```

`PORT(S)` 가 `80:30080/TCP` — 클러스터 내부 80, 노드 외부 30080.

> **🧠 NodePort는 "모든" 노드에서 열림**
> Pod이 노드 A에만 있어도, 노드 B의 30080으로 들어온 요청을 kube-proxy가 노드 A로 다시 전달함.
> 즉 외부 LB는 노드 IP 아무거나 아니라 모든 노드 풀에 트래픽 보내도 OK.
> 단, `externalTrafficPolicy: Local` 로 두면 자기 노드에 Pod 없으면 패킷 드롭 (소스 IP 보존 + hop 절감 효과).

## 2. NodePort로 접근 시도

EKS 노드의 SG는 기본적으로 **30080 포트가 막혀있을 수 있습니다**. 임시로 열기:

```bash
# 노드 SG ID 찾기 (한 노드 기준)
NODE_NAME=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=private-dns-name,Values=${NODE_NAME}" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
SG_ID=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[].Instances[].SecurityGroups[].GroupId' --output text | awk '{print $1}')

echo "Node SG: $SG_ID"

# 30080 포트 임시 오픈 (학습용. 실무 금지)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 30080 --cidr 0.0.0.0/0

# 노드 퍼블릭 IP
NODE_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
  --query 'Reservations[].Instances[].PublicIpAddress' --output text)
echo "Node IP: $NODE_IP"

curl http://$NODE_IP:30080/
```

> **운영에서는** NodePort를 인터넷에 직접 노출하지 않습니다. LoadBalancer/Ingress 사용.

> **🧠 NodePort 인터넷 노출이 안 좋은 이유**
> 1. SG를 직접 열어야 함 (모든 노드 IP 관리 부담).
> 2. 노드 IP가 변경되면 클라이언트도 갱신 필요 (Auto Scaling 환경에 부적합).
> 3. TLS, WAF, sticky session 같은 LB 기능 없음.
> = NodePort는 내부 통신용 또는 LoadBalancer/Ingress 의 백엔드로만 쓴다고 생각하면 됨.

테스트 끝나면 SG 룰 회수:
```bash
aws ec2 revoke-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp --port 30080 --cidr 0.0.0.0/0
```

## 3. LoadBalancer 배포

```bash
kubectl apply -f manifests/loadbalancer.yaml
kubectl get svc web-lb --watch     # EXTERNAL-IP 가 채워질 때까지 대기 (1~3분)
```

> **🧠 EXTERNAL-IP 가 채워지는 메커니즘**
> 1. K8s에 LoadBalancer 타입 Service 등록됨.
> 2. AWS Cloud Controller Manager(CCM)가 이를 watch하고 있다가 → AWS ELB API 호출 → NLB/CLB 생성.
> 3. 만들어진 LB의 DNS를 Service.status.loadBalancer.ingress 에 기록 → EXTERNAL-IP 채워짐.
> 어노테이션 `service.beta.kubernetes.io/aws-load-balancer-type: nlb` 가 NLB를 명시. 없으면 옛 CLB 만들 수도.

기대 (시간 지나면):
```
NAME      TYPE           CLUSTER-IP       EXTERNAL-IP                                                        PORT(S)        AGE
web-lb    LoadBalancer   10.100.55.123    a1b2c3d4e5...elb.ap-northeast-2.amazonaws.com   80:31234/TCP   2m
```

## 4. LB DNS로 외부 접근

```bash
LB_DNS=$(kubectl get svc web-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "LB: $LB_DNS"

curl http://$LB_DNS/
```

기대: nginx 페이지 또는 `web-xxx` (lab-01에서 hostname 주입했다면).

## 5. AWS 콘솔에서 NLB 확인

```bash
aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(DNSName, `'$LB_DNS'`)].[LoadBalancerName,Type,Scheme,State.Code]' \
  --output table
```

또는 콘솔: EC2 → Load Balancers → 방금 만든 NLB 선택 → Listener / Target group 확인.

**Target group의 health check** 가 통과해야 LB가 트래픽을 보냅니다. 처음에는 `Initial` 또는 `Unhealthy` 일 수 있고 30초~1분 후 `Healthy` 로 전환.

> **🧠 health check가 두 종류**
> - **K8s readinessProbe**: kubelet이 Pod 자체를 체크 → 실패 시 Endpoints에서 빠짐.
> - **AWS Target Group health check**: NLB가 노드 NodePort를 체크 → 실패 시 LB가 그 노드에 트래픽 안 보냄.
> 둘 다 통과해야 사용자 요청이 도달함. 운영 디버깅 시 두 군데 모두 확인 필수.

## 6. `kubectl describe` 로 어노테이션 확인

```bash
kubectl describe svc web-lb | grep -A20 'Annotations\|Selector\|Type\|LoadBalancer Ingress'
```

매니페스트에서 준 어노테이션이 그대로 있고, 그 결과 NLB가 만들어졌습니다.

## 7. 정리 (반드시!)

```bash
kubectl delete -f manifests/loadbalancer.yaml
kubectl delete -f manifests/nodeport.yaml
```

LB가 실제로 사라졌는지 확인:
```bash
sleep 30
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output text
```

기대: 우리가 만든 LB는 보이지 않음.

## 학습 확인 질문

1. LoadBalancer 타입 Service는 NodePort 와 ClusterIP를 함께 만드나?
2. 인터넷 노출 시 NodePort 직접 사용을 권하지 않는 이유 두 가지?
3. `kubectl delete svc web-lb` 만으로 NLB가 정말로 삭제되는 메커니즘은? (어떤 컴포넌트가 그 일을 함?)

다음: [lab-03-dns.md](./lab-03-dns.md)
