# Lab 02 — EKS 감사 로그와 APF

## Part A. 감사 로그 (Audit)

### Step 1. EKS control plane 로깅 켜기

```bash
aws eks update-cluster-config --name k8s-study --region ap-northeast-2 \
  --logging '{"clusterLogging":[{"types":["audit","authenticator"],"enabled":true}]}'
# 적용 대기 (~수 분)
aws eks describe-cluster --name k8s-study --region ap-northeast-2 \
  --query 'cluster.logging.clusterLogging[?enabled==`true`].types' --output json
```

> 💰 비용: CloudWatch Logs 수집/보관 요금 발생 (audit는 수다스럽습니다). 실습 후 끄는 것을 cleanup에 포함.

### Step 2. 추적 대상 행동 만들기

```bash
kubectl create secret generic audit-bait --from-literal=k=v
kubectl get secret audit-bait -o yaml >/dev/null     # "Secret을 읽는" 행위
kubectl delete secret audit-bait
```

### Step 3. "누가 그 Secret을 읽었나" 조회

```bash
LOG_GROUP=/aws/eks/k8s-study/cluster
aws logs filter-log-events --region ap-northeast-2 \
  --log-group-name $LOG_GROUP \
  --log-stream-name-prefix kube-apiserver-audit \
  --filter-pattern '{ $.objectRef.name = "audit-bait" }' \
  --query 'events[].message' --output text | head -3 | python3 -m json.tool 2>/dev/null || \
aws logs filter-log-events --region ap-northeast-2 \
  --log-group-name $LOG_GROUP \
  --log-stream-name-prefix kube-apiserver-audit \
  --filter-pattern 'audit-bait' \
  --query 'events[0].message' --output text
```

예상 출력에서 볼 것 (JSON 필드):
```json
{
  "verb": "get",
  "user": { "username": "arn:aws:iam::...:user/me", "groups": [...] },   ← IAM 신원!
  "objectRef": { "resource": "secrets", "name": "audit-bait" },
  "responseStatus": { "code": 200 },
  "sourceIPs": [...], "stageTimestamp": "..."
}
```

✅ **get/create/delete가 IAM ARN과 함께 전부 기록**되어 있습니다. 보안 사고 시 "유출 시점에 그 Secret을 읽은 모든 주체" 조회가 이 한 쿼리입니다. EKS는 K8s 감사와 IAM 신원이 연결되는 것이 강점.

## Part B. APF 관찰

### Step 4. 내 요청이 어느 줄에 서는지

```bash
kubectl get pods -v=8 2>&1 | grep -iE "x-kubernetes-pf" | head -2
```

예상 출력 (응답 헤더):
```
X-Kubernetes-Pf-Flowschema-Uid: ...
X-Kubernetes-Pf-Prioritylevel-Uid: ...
```

✅ 모든 응답에 "어느 FlowSchema/우선순위로 분류됐는지"가 찍힙니다.

### Step 5. 분류 체계 구경

```bash
kubectl get flowschemas --sort-by=.spec.matchingPrecedence | head -12
kubectl get prioritylevelconfigurations
```

예상: `system-leader-election`, `system-nodes`(kubelet!), `workload-high`, `catch-all` 등 — 시스템 생명선들이 **전용 예산**을 가진 구조. 일반 사용자(kubectl)는 보통 `global-default`입니다. 위 헤더의 UID와 대조해 내 줄을 확인해보세요.

### Step 6. (관찰) 과부하 시 무슨 일이

부하를 실제로 걸어 429를 만드는 것은 공유 클러스터에서 권장하지 않으므로, 메커니즘만 정리:

```
폭주 클라이언트 → 그 FlowSchema의 예산 소진 → 큐 대기 → 큐도 차면 429 + Retry-After
다른 FlowSchema(kubelet 등)는 자기 예산으로 정상 처리
```

운영 신호: API 응답에 429가 보이면 `apiserver_flowcontrol_rejected_requests_total` 메트릭으로 **어느 분류가** 거절당하는지 → 폭주 주체 식별 (대개 잘못 짠 컨트롤러/CI의 LIST 폭탄).

## 정리

```bash
bash cleanup.sh    # audit 로깅 비활성화 포함
```
