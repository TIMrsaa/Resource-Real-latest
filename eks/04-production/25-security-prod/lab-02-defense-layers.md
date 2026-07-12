# Lab 02 — 침해 시나리오: 벽을 하나씩 세우며 공격을 막습니다

공격자가 되어 봅니다. **아무 방어도 없는 상태**에서 시작해 침해를 완주한 뒤, 관문을 하나씩 세우며 같은 공격이 어디서 멈추는지 확인합니다 — 심층 방어의 각 층이 왜 필요한지 몸으로.

## Step 0. 공격 시나리오

```
가정: 앱의 RCE 취약점으로 공격자가 Pod 안에서 명령 실행 능력을 얻었습니다.
목표: ① 노드 IAM 자격증명 탈취(IMDS)  ② 다른 ns로 측면 이동  ③ privileged로 노드 장악
```

## Step 1. 무방비 상태 — 침해 완주

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: attacker
  namespace: seclab
  labels: { run: attacker }
spec:
  containers:
    - name: attacker
      image: ghcr.io/nicolaka/netshoot:latest
      command: ["sleep", "3600"]
EOF
kubectl wait --for=condition=Ready pod/attacker -n seclab --timeout=60s

# ① IMDS로 노드 자격증명 탈취 시도
kubectl exec -n seclab attacker -- sh -c '
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" --max-time 3)
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/ --max-time 3
' || echo "IMDS 접근 실패"
```

hop limit이 기본(2)이면 **역할 이름이 출력됩니다** — 그 아래 경로로 AccessKey까지 얻을 수 있습니다. 이것이 EKS 침해의 고전 1단계(theory §4).

```bash
# ② 측면 이동: 다른 ns의 서비스 스캔
kubectl exec -n seclab attacker -- nc -zv -w2 kubernetes.default.svc 443 2>&1 | tail -1
# ③ privileged Pod로 노드 장악 시도 (RBAC이 허용한다면)
kubectl apply -f - 2>&1 <<'EOF' | tail -1
apiVersion: v1
kind: Pod
metadata:
  name: escape
  namespace: seclab
  labels: { run: escape }
spec:
  hostPID: true
  containers:
    - name: e
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "60"]
      securityContext:
        privileged: true
EOF
```

세 갈래가 다 열려 있다면 — 이 클러스터는 Pod 하나의 RCE가 **AWS 계정 침해**로 번집니다.

## Step 2. 관문 ③ — PSA로 탈출 도구 압수 (32)

```bash
kubectl label ns seclab \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted --overwrite

kubectl delete pod escape -n seclab --ignore-not-found
kubectl apply -f - 2>&1 <<'EOF' | tail -2
apiVersion: v1
kind: Pod
metadata:
  name: escape
  namespace: seclab
  labels: { run: escape }
spec:
  hostPID: true
  containers:
    - name: e
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "60"]
      securityContext:
        privileged: true
EOF
```

예상: `Forbidden ... violates PodSecurity "restricted"` — ③ 봉쇄. privileged·hostPID·hostPath라는 **탈출 사다리**가 사라졌습니다.

## Step 3. 관문 ④ — NetworkPolicy로 측면 이동 차단 (15·18)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny-egress, namespace: seclab }
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to: [{ namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: kube-system } } }]
    ports: [{ protocol: UDP, port: 53 }]     # DNS만 허용
EOF
sleep 10
kubectl exec -n seclab attacker -- nc -zv -w2 kubernetes.default.svc 443 2>&1 | tail -1 || echo "측면 이동 BLOCKED"
```

예상: 차단 — ④ 봉쇄. 침해된 Pod가 클러스터를 정찰할 수 없습니다. (egress 기본 거부는 강력하지만 앱의 정당한 외부 호출도 막으므로 allowlist 설계가 뒤따라야 합니다)

## Step 4. 관문 ⑤ — IMDS 차단: 가장 중요한 한 줄

두 가지 방법. **노드 수준(권장, hop limit)**:

```bash
# 노드의 인스턴스에 hop limit 1 강제 → 컨테이너(추가 홉)에서 IMDS 도달 불가
NODE=$(kubectl get pod attacker -n seclab -o jsonpath='{.spec.nodeName}')
IID=$(kubectl get node $NODE -o jsonpath='{.spec.providerID}' | awk -F/ '{print $NF}')
aws ec2 modify-instance-metadata-options --region ap-northeast-2 --instance-id $IID \
  --http-put-response-hop-limit 1 --http-tokens required --http-endpoint enabled

sleep 5
kubectl exec -n seclab attacker -- sh -c '
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" --max-time 3)
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/ --max-time 3
' || echo "IMDS BLOCKED — 노드 역할 탈취 실패"
```

예상: 실패 — ① 봉쇄. ✅ 이 한 줄이 "Pod RCE → AWS 계정 침해"의 사슬을 끊습니다. (NetworkPolicy egress로 169.254.169.254를 막는 것도 보조 수단이지만, hop limit이 근본)

## Step 5. 관문 ① — admission으로 이미지 출처 강제 (23)

공격의 시작점(악성 이미지)도 막자 — 신뢰 레지스트리만:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata: { name: trusted-registries }
spec:
  matchConstraints:
    resourceRules:
    - { apiGroups: [""], apiVersions: ["v1"], operations: ["CREATE"], resources: ["pods"] }
  validations:
  - expression: >-
      object.spec.containers.all(c,
        c.image.startsWith('public.ecr.aws/') || c.image.startsWith('ghcr.io/stefanprodan/'))
    message: "허용되지 않은 레지스트리입니다"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata: { name: trusted-registries }
spec:
  policyName: trusted-registries
  validationActions: [Deny]
  matchResources:
    namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: seclab } }
EOF
sleep 5
kubectl run evil -n seclab --image=docker.io/evil/miner:latest 2>&1 | tail -1
```

예상: `denied ... 허용되지 않은 레지스트리` — ① 봉쇄.

## Step 6. 관문 ⑥ — 탐지: 감사 로그를 수사 자료로 (12·21)

방어를 뚫렸다고 가정할 때 **얼마나 빨리 아는가**. Logs Insights 쿼리 세트(감사 로그 활성화 시):

```
# 익명 성공 요청 — 즉시 사고
fields @timestamp, user.username, verb, objectRef.resource
| filter user.username = "system:anonymous" and responseStatus.code < 300

# exec 남용 — 누가 어느 Pod에 들어갔나
| filter objectRef.subresource = "exec"

# 권한 상승의 발자국
| filter objectRef.resource = "clusterrolebindings" and (verb = "create" or verb = "update")
```

GuardDuty EKS Protection이 켜져 있다면 이 패턴들 상당수가 **Finding으로 자동 승격**됩니다 — 그리고 Finding → EventBridge → 자동 격리(Pod에 deny-all NetworkPolicy + 노드 cordon + 포렌식 스냅샷)가 대응 설계의 뼈대(theory §3).

## Step 7. 방어선 점검표 (산출물)

```markdown
# 심층 방어 점검표 — 우리 클러스터
| 관문 | 현재 | 목표 | 검증 방법 |
|------|------|------|----------|
| ① 공급망 | | ECR 스캔 + VAP 레지스트리 제한 + 서명 검증 | Step 5의 evil pod 거부 |
| ② 신원 | | 노드 역할 최소화, 워크로드는 IRSA/PI, 자원 ARN 단위 | 09 |
| ③ 워크로드 | | 전 ns PSA restricted (예외는 명시·기한부) | Step 2의 escape 거부 |
| ④ 네트워크 | | ns별 default-deny + allowlist | Step 3 |
| ⑤ 시크릿 | | Secrets Manager CSI (lab-01) + etcd KMS 암호화 | 클러스터에 원본 없음 확인 |
| ⑥ 탐지 | | GuardDuty EKS + 감사 쿼리 알람 + 자동 격리 | 분기 침해 훈련 |
★ 최우선 한 줄: IMDS hop limit=1 (Step 4) — 사슬을 끊는 지점
```

## 정리

```bash
bash cleanup.sh
```
