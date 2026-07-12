# Lab 02 — NodePort와 LoadBalancer(NLB)로 외부 노출

> **비용 주의**: Step 3의 NLB는 시간당 ~$0.0225 + 데이터 처리비. 실습 후 즉시 삭제.

## Step 1. NodePort — 모든 노드에 같은 구멍

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: echo-np
spec:
  type: NodePort
  selector: { app: echo }
  ports:
    - port: 80
      targetPort: 8080
EOF
kubectl get svc echo-np
```

예상 출력:
```
NAME      TYPE       CLUSTER-IP     PORT(S)        
echo-np   NodePort   172.20.yy.yy   80:31234/TCP    ← 30000~32767 중 자동 할당
```

✅ ClusterIP도 같이 생겼습니다 — "NodePort = ClusterIP + 노드 포트"의 증거.

```bash
# 노드 안에서 노드IP:31234로 호출 (보안그룹이 외부 접근은 막고 있으므로 내부에서 검증)
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
NODE_PORT=$(kubectl get svc echo-np -o jsonpath='{.spec.ports[0].nodePort}')
kubectl run np-test --rm -it --image=public.ecr.aws/docker/library/busybox:stable --restart=Never -- \
  wget -qO- http://$NODE_IP:$NODE_PORT/hostname
```

예상: echo Pod 이름 응답. **어느 노드 IP로 호출해도** 동작합니다(그 노드에 echo Pod가 없어도 전달됨).

> 💡 외부 인터넷에서 NodePort로 직접 접속하려면 노드 보안그룹 인바운드를 열어야 합니다 — 실무에서 그렇게 안 하는 이유: 노드 IP도 결국 바뀌는 소모품이고, 보안그룹 관리가 지옥이 됩니다. 그래서 다음 단계가 존재합니다.

## Step 2. LoadBalancer — 실제 AWS NLB 생성

> ⚠️ **중요**: 어노테이션 없이 `--type=LoadBalancer`만 쓰면 in-tree cloud-controller-manager가 **Classic Load Balancer(CLB)**를 만듭니다(NLB가 아님). NLB를 만들려면 아래 `service.beta.kubernetes.io/aws-load-balancer-type: "nlb"` 어노테이션이 필요합니다. (AWS Load Balancer Controller는 eks 파트 08에서 설치하므로, 지금은 이 어노테이션으로 in-tree NLB 모드를 씁니다.)

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: echo-lb
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"   # ← 이 줄이 없으면 Classic ELB가 생성됨
spec:
  type: LoadBalancer
  selector:
    app: echo
  ports:
  - port: 80
    targetPort: 8080
EOF
kubectl get svc echo-lb -w     # EXTERNAL-IP가 <pending> → 주소로 바뀔 때까지 (~2분)
```

예상 출력:
```
NAME      TYPE           CLUSTER-IP    EXTERNAL-IP                                       PORT(S)
echo-lb   LoadBalancer   172.20.zz.zz  xxxxxxxx.elb.ap-northeast-2.amazonaws.com         80:32456/TCP
```

✅ EXTERNAL-IP 자리에 **AWS NLB의 DNS 이름**이 들어왔습니다. NodePort(32456)도 같이 생겼습니다 — NLB가 그 NodePort로 노드들에 전달하는 구조.

```bash
# AWS 쪽 실체 확인
aws elbv2 describe-load-balancers --region ap-northeast-2 \
  --query 'LoadBalancers[?Type==`network`].[LoadBalancerName,DNSName]' --output table
```

## Step 3. 인터넷에서 진짜 호출

```bash
LB=$(kubectl get svc echo-lb -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
# DNS 전파 대기 후 (1~3분)
curl -s http://$LB/hostname; echo
for i in $(seq 1 6); do curl -s http://$LB/hostname; echo; done
```

예상 출력: 여러분의 PC(클러스터 밖!)에서 echo Pod 이름들이 응답.

✅ **외부 → NLB → NodePort → iptables → Pod** 전체 경로 완성. 인터넷에 서비스를 노출했습니다.

## Step 4. 누가 NLB를 만들었나 — 이벤트로 범인 찾기

```bash
kubectl describe svc echo-lb | grep -A 5 Events
```

예상 출력:
```
Type    Reason                Message
Normal  EnsuringLoadBalancer  Ensuring load balancer
Normal  EnsuredLoadBalancer   Ensured load balancer
```

이 작업의 주체가 cloud-controller-manager(모듈 02 이론의 그 컴포넌트)입니다. EKS에서 운영 표준은 별도의 **AWS Load Balancer Controller**(더 많은 기능: Pod 직접 타겟, ALB 등)인데, 그것은 eks 파트 08에서 설치/해부합니다.

## Step 5. 비용 정리 — LB는 들고 있는 것만으로 돈이 나갑니다

```bash
kubectl delete svc echo-lb       # ← Service 삭제가 NLB 삭제로 이어지는지 확인
aws elbv2 describe-load-balancers --region ap-northeast-2 \
  --query 'length(LoadBalancers)'
```

✅ Service를 지우면 컨트롤러가 NLB도 지웁니다. **클러스터를 통째로 지울 때 LB Service를 먼저 안 지우면 NLB가 고아로 남아 과금되는** 사고가 흔합니다 — cleanup 습관의 이유.

## 트러블슈팅

| 증상 | 원인/해결 |
|------|----------|
| EXTERNAL-IP가 `<pending>`에서 안 바뀜 | 서브넷 태그 누락 등 — `kubectl describe svc`의 Events에 에러 사유가 찍힘 |
| curl 타임아웃 | DNS 전파 대기 (dig로 확인) / NLB 헬스체크가 아직 unhealthy |
| 보안그룹 어디서 났지? | eksctl이 노드 SG에 NLB 헬스체크/트래픽 규칙을 자동 추가 |

## 정리

```bash
bash cleanup.sh
```
