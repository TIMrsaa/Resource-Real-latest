# 흔한 함정 5선 — 02. Service & Networking

## 1. Service는 만들어졌는데 호출하면 응답이 없다

**증상**: Service의 ClusterIP에 `curl` 해도 hang 또는 connection refused.

**원인 1**: Endpoints가 비어있음.
```bash
kubectl get endpoints my-svc
# 결과가 <none> 이면 → Pod가 매칭 안 됨
```

진단:
```bash
kubectl get pods --show-labels
kubectl get svc my-svc -o yaml | yq '.spec.selector'
```

라벨이 100% 일치해야 함. `app: web` vs `app: my-web` 같은 차이도 매칭 안 됨.

**원인 2**: Pod가 Ready가 아님 (readinessProbe 실패).
```bash
kubectl get pods -l app=web    # READY 컬럼이 1/1 인지
```

readinessProbe 실패한 Pod는 Endpoints에서 자동 제외됩니다.

**원인 3**: targetPort가 컨테이너 실제 포트와 다름.
```bash
kubectl get svc my-svc -o yaml | yq '.spec.ports'
# targetPort: 8080
kubectl get pod <p> -o yaml | yq '.spec.containers[].ports'
# containerPort: 80    ← 불일치!
```

---

## 2. LoadBalancer Service의 EXTERNAL-IP가 영영 `<pending>`

**증상**:
```
NAME     TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
web-lb   LoadBalancer   10.100.55.123   <pending>     80:31234/TCP   10m
```

**원인 후보**:
- EKS 클러스터의 IAM Role에 LB 생성 권한 없음 (cluster role / node role 점검)
- AWS Load Balancer Controller 가 설치되어 있는데 ServiceAccount IAM Role이 잘못됨
- 서브넷 태그 누락 — public LB는 서브넷에 `kubernetes.io/role/elb=1` 태그 필요

**진단**:
```bash
kubectl describe svc web-lb           # Events 섹션
kubectl logs -n kube-system deploy/aws-load-balancer-controller --tail=50    # 컨트롤러가 있다면
```

EKS의 in-tree CCM이 LB를 만들 때는 노드 IAM Role의 권한이 사용됩니다.

---

## 3. Pod에서 외부 인터넷으로 못 나감

**증상**: `kubectl exec ... -- curl https://google.com` 이 timeout.

**원인 후보**:
- 노드가 private subnet에 있고 NAT Gateway 없음
- 클러스터 보안그룹이 outbound 차단
- VPC endpoint가 잘못 설정 (DNS 충돌)

**진단**:
```bash
# 노드의 서브넷
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
INSTANCE=$(aws ec2 describe-instances --filters "Name=private-dns-name,Values=$NODE" --query 'Reservations[].Instances[].InstanceId' --output text)
SUBNET=$(aws ec2 describe-instances --instance-ids $INSTANCE --query 'Reservations[].Instances[].SubnetId' --output text)

# 라우팅 테이블에 0.0.0.0/0 → NAT/IGW 가 있는지
aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$SUBNET" \
  --query 'RouteTables[].Routes' --output table
```

---

## 4. CoreDNS Pod이 죽어있어 모든 워크로드 영향

**증상**: 워크로드 전체가 외부 호출/내부 Service 호출 모두 실패.

**진단**:
```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
```

흔한 원인:
- CoreDNS Pod가 `OOMKilled` (deployment의 limits 너무 낮음 + 큰 클러스터)
- Liveness probe가 너무 빡빡

해결:
```bash
kubectl edit deploy -n kube-system coredns
# resources.limits.memory 를 늘림 (기본 170Mi → 256Mi 등)
```

대규모 클러스터(수천 Service)는 `coredns-autoscaler` 도입 검토.

---

## 5. Headless Service인데 일반 Service처럼 동작 안 함

**Headless Service**: `clusterIP: None` 으로 만들면 ClusterIP 가상 IP 없이 DNS만 제공. StatefulSet에서 자주 사용.

**증상**: `nslookup my-headless` 에서 다중 A 레코드(Pod별)를 기대했는데 NXDOMAIN.

**원인**:
- StatefulSet과 Service의 selector 불일치
- Pod가 Ready 가 아님 → DNS에서도 제외 (단, `publishNotReadyAddresses: true` 옵션으로 강제 노출 가능)

**진단**:
```bash
kubectl get svc my-headless -o yaml | yq '.spec.{clusterIP,selector,publishNotReadyAddresses}'
kubectl get endpoints my-headless
```

**Headless Service 예시** (Part 1 03 모듈에서 다룸):
```yaml
apiVersion: v1
kind: Service
metadata:
  name: redis-hl
spec:
  clusterIP: None      # ← Headless
  selector:
    app: redis
  ports:
    - port: 6379
```

이러면 `redis-0.redis-hl`, `redis-1.redis-hl` 처럼 Pod별 DNS 레코드가 자동 생성 (StatefulSet일 때).
