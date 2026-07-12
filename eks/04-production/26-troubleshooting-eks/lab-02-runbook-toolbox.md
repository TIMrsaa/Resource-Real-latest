# Lab 02 — 도구상자를 짓고, 온콜을 리허설합니다

진단은 지식이 아니라 **손이 기억하는 절차**여야 합니다. 도구를 상시 배치하고, 증거를 잃지 않는 습관을 만들고, 온콜 시나리오로 리허설합니다.

## Step 1. 상시 도구 — 진단 Pod을 미리 준비

장애 순간에 이미지를 고르고 있으면 늦습니다. 팀 표준 진단 Pod:

```bash
cat > toolbox.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: toolbox
  namespace: default
  annotations:
    karpenter.sh/do-not-disrupt: "true"      # 17 — 진단 중에 사라지면 곤란
spec:
  containers:
  - name: nettools
    image: ghcr.io/nicolaka/netshoot:latest   # ping/dig/traceroute/ss/tcpdump/curl
    command: [sleep, "infinity"]
    resources: { requests: { cpu: 50m, memory: 64Mi } }
EOF
kubectl apply -f toolbox.yaml
kubectl wait --for=condition=Ready pod/toolbox --timeout=60s

# 즉시 쓸 수 있는 3종
kubectl exec toolbox -- dig +short kubernetes.default.svc.cluster.local
kubectl exec toolbox -- curl -s -o /dev/null -w "%{http_code}\n" -m3 https://kubernetes.default.svc/livez -k
```

노드 안이 필요할 땐(SSH 없이):

```bash
NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl debug node/$NODE -it --image=ghcr.io/nicolaka/netshoot:latest -- ip route | head -5
```

## Step 2. 증거 보전 — 이벤트는 1시간 후 사라집니다

장애 대응의 첫 명령은 진단이 아니라 **수집**이어야 합니다:

```bash
cat > collect.sh <<'EOF'
#!/usr/bin/env bash
# 장애 스냅샷 수집 — 조사 전에 먼저 돌립니다 (이벤트는 ~1h 후 소멸)
set -euo pipefail
NS=${1:-default}; OUT="incident-$(date +%Y%m%d-%H%M%S)"
mkdir -p $OUT
kubectl get events -A --sort-by=.lastTimestamp > $OUT/events-all.txt
kubectl get pods -A -o wide            > $OUT/pods.txt
kubectl get nodes -o wide              > $OUT/nodes.txt
kubectl describe nodes                 > $OUT/nodes-describe.txt
kubectl get pdb,hpa -A                 > $OUT/pdb-hpa.txt
kubectl top nodes 2>/dev/null          > $OUT/top-nodes.txt || true
kubectl logs -n kube-system ds/aws-node -c aws-node --tail=200 > $OUT/ipamd.txt 2>/dev/null || true
for p in $(kubectl get pods -n $NS --field-selector status.phase!=Running -o name); do
  kubectl describe $p -n $NS >> $OUT/unhealthy-describe.txt
  kubectl logs $p -n $NS --previous --tail=100 >> $OUT/unhealthy-logs.txt 2>/dev/null || true
done
echo "수집 완료: $OUT"
EOF
chmod +x collect.sh && ./collect.sh default
```

✅ 이 스크립트가 있는 팀과 없는 팀의 차이 — 사후 분석에서 "그때 이벤트를 못 봤다"가 사라집니다.

## Step 3. 온콜 리허설 — 카드 없이 판정해보기

동료가 아래 증상 중 하나를 골라 클러스터에 만들고(또는 말로 제시), 당신은 **3분 안에 계층을 판정**하고 확진 명령 하나를 대야 합니다. 답은 theory의 카드.

```markdown
# 리허설 문제 (증상만 주어짐)
1. "배포는 성공인데 새 Pod가 ContainerCreating에서 10분째"
2. "앱 로그에 AccessDenied. 어제까진 됐어요"
3. "ALB에서 502가 배포할 때마다 30초쯤 나요"
4. "노드 세 대가 동시에 NotReady"
5. "가끔 DNS가 안 됩니다. 재시도하면 되고요"
6. "kubectl로 CoreDNS 고쳤는데 며칠 뒤 원복됐어요"
7. "StatefulSet Pod가 FailedAttachVolume"
8. "부하가 3배인데 HPA가 안 늘어요"
9. "A ns에서 B ns 서비스로 타임아웃. DNS는 됩니다"
10. "Karpenter가 노드를 안 만들어요. Pending만 쌓여요"

# 채점: 계층 판정(④③②①) + 확진 명령 1개 + 처방 방향
```

각 문제의 **첫 질문은 언제나 같습니다**: "어제까지 됐나요? 뭘 바꿨나요?"(theory §3) — 2번은 그 질문 하나로 IAM 정책 변경 이력(CloudTrail)에 도달합니다.

## Step 4. 진단 카드를 팀 위키로 (산출물)

```markdown
# EKS 온콜 카드 (theory §2를 팀 컨텍스트로 채운 판)
| # | 증상 | 확진 명령 | 처방 | 우리 클러스터 메모 |
|---|------|----------|------|------------------|
| 1 | ContainerCreating 정지 | describe-subnets AZ별 min | 16 | 병목 AZ: __ , 현재 여유 __ |
| 2 | Pending/Insufficient | describe pod events + karpenter logs | 17/22 | NodePool limits: __ |
| 3 | AccessDenied | exec env grep AWS_ → association | 09 | 우리 표준: Pod Identity |
| 4 | 502/503 | elb vs target status code | 14 | readiness gate 적용 ns: __ |
| ... | (10장 전부) | | | |

## 대응 절차
0. collect.sh 실행 (증거 보전!)  1. 계층 판정  2. 확진  3. 처방  4. 사후: 카드에 메모 추가
## 에스컬레이션
- AWS 인프라 의심(①) 시: Health Dashboard 확인 → 서포트 케이스(클러스터 ARN·시각·Flow Logs 첨부)
```

## Step 5. 졸업 확인 — 이 파트가 준 것

```markdown
26개 모듈이 이 카드 10장으로 수렴합니다:
카드1←16 / 2←17,22 / 3←09 / 4←14 / 5←05,02 / 6←k8s16 / 7←11 / 8←10 / 9←18 / 10←15,17
→ 진단력은 지식의 양이 아니라 **경계를 아는 것**에서 나옵니다.
```

## 정리

```bash
bash cleanup.sh
```
