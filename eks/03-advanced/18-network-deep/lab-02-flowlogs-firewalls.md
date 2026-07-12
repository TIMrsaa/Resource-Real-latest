# Lab 02 — CCTV 켜기: Flow Logs 심문과 검문소의 비대칭

VPC Flow Logs를 켜고 세 가지를 목격합니다: 정상 트래픽의 기록(ACCEPT), 인터넷의 소음(REJECT), 그리고 **NetworkPolicy 드롭이 CCTV에 안 찍히는** 순간 — 진단 계단의 근거가 되는 비대칭입니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
VPC=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION --query 'cluster.resourcesVpcConfig.vpcId' --output text)
```

## Step 1. Flow Logs 켜기 (CW Logs로 — 12의 파이프라인 재사용)

```bash
# 로그 그룹 + Flow Logs용 IAM 역할
aws logs create-log-group --log-group-name /vpc/flowlogs-lab --region $AWS_REGION
aws logs put-retention-policy --log-group-name /vpc/flowlogs-lab --retention-in-days 3 --region $AWS_REGION   # 12의 규율!

cat > fl-trust.json <<'EOF'
{ "Version": "2012-10-17", "Statement": [{ "Effect": "Allow",
  "Principal": { "Service": "vpc-flow-logs.amazonaws.com" }, "Action": "sts:AssumeRole" }]}
EOF
aws iam create-role --role-name FlowLogsLab --assume-role-policy-document file://fl-trust.json 2>/dev/null || true
aws iam put-role-policy --role-name FlowLogsLab --policy-name write-logs --policy-document '{
  "Version":"2012-10-17","Statement":[{"Effect":"Allow",
  "Action":["logs:CreateLogStream","logs:PutLogEvents","logs:DescribeLogGroups","logs:DescribeLogStreams"],"Resource":"*"}]}'
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws ec2 create-flow-logs --region $AWS_REGION --resource-type VPC --resource-ids $VPC \
  --traffic-type ALL --log-group-name /vpc/flowlogs-lab \
  --deliver-logs-permission-arn arn:aws:iam::$ACCOUNT_ID:role/FlowLogsLab
```

## Step 2. 기록될 트래픽 만들기 — 정상 + NP 차단

lab-01의 pod-a/b/c에 트래픽을 흘리고, **pod-c만 NetworkPolicy로 잠급니다**:

```bash
# c에서 웹서버 하나
kubectl exec -n netlab pod-c -- sh -c "python3 -m http.server 8080 >/dev/null 2>&1 &"

# 정상: a→c 접속 (아직 정책 없음)
kubectl exec -n netlab pod-a -- curl -s -m3 -o /dev/null -w "%{http_code}\n" http://$C:8080/   # 200

# NP 잠금 — netlab의 default-deny (k8s 15의 그 리소스, 집행자만 VPC CNI eBPF)
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: deny-all, namespace: netlab }
spec:
  podSelector: { matchLabels: { run: pod-c } }
  policyTypes: [Ingress]
EOF
sleep 10
kubectl exec -n netlab pod-a -- curl -s -m3 -o /dev/null -w "%{http_code}\n" http://$C:8080/ || echo "BLOCKED"
```

예상: 200 → **BLOCKED(타임아웃)** — eBPF 문지기가 일합니다. (막히지 않으면 NP 집행이 꺼진 것: 애드온 설정 `enableNetworkPolicy` 확인 — 11의 configuration-values)

## Step 3. 심문 ① — 그 차단, CCTV에 찍혔나요?

로그 전파를 5분쯤 기다린 뒤 Logs Insights(12의 그 도구)로:

```bash
QID=$(aws logs start-query --region $AWS_REGION --log-group-name /vpc/flowlogs-lab \
  --start-time $(($(date +%s)-900)) --end-time $(date +%s) \
  --query-string "fields @timestamp, srcAddr, dstAddr, dstPort, action
| filter srcAddr = '$A' and dstAddr = '$C' and dstPort = 8080
| sort @timestamp desc | limit 10" --query queryId --output text)
sleep 10; aws logs get-query-results --region $AWS_REGION --query-id $QID --output table
```

예상: 차단 이후의 시도까지 **전부 `ACCEPT`** — SG는 통과시켰고, 드롭은 그 뒤(veth의 eBPF)에서 일어났기 때문. ✅ **theory §5의 비대칭을 증거로 확보**: "Flow Logs ACCEPT + 불통 = NP를 심문하라". NP 쪽의 진실은 노드의 network-policy-agent 로그/메트릭에 있습니다.

## Step 4. 심문 ② — 인터넷의 소음 (진짜 REJECT 구경)

퍼블릭 ENI가 있는 VPC라면 우리가 아무것도 안 해도 REJECT가 쌓입니다 — 전 세계 스캐너들 덕분에:

```bash
QID=$(aws logs start-query --region $AWS_REGION --log-group-name /vpc/flowlogs-lab \
  --start-time $(($(date +%s)-900)) --end-time $(date +%s) \
  --query-string "fields srcAddr, dstPort
| filter action = 'REJECT'
| stats count(*) as hits by srcAddr, dstPort
| sort hits desc | limit 10" --query queryId --output text)
sleep 10; aws logs get-query-results --region $AWS_REGION --query-id $QID --output table
```

예상: 낯선 해외 IP들이 22/23/3389/8088… 포트를 두드리고 SG가 **REJECT**한 기록. ✅ REJECT = SG/NACL의 소행이라는 규칙 + "퍼블릭 ENI는 상시 노크당한다"는 현실 감각(25 보안 모듈의 복선).

## Step 5. 진단 계단 리허설 (산출물)

방금의 도구들로 theory §7을 리허설해 몸에 붙입니다:

```markdown
# "A→B 불통" 진단 계단 — 명령 매핑
0. DNS      kubectl exec A -- nslookup b-svc      (실패 → 16 CoreDNS)
1. NP       kubectl get netpol -n <B의 ns>        (deny 있고 A 미허용? → 범인)
2. SG       B 노드/Pod의 SG 인바운드 규칙          (그 포트 허용?)
3. NACL     서브넷 다르면 양방향+ephemeral 확인
4. 라우팅    VPC/피어링 라우트 테이블
5. 증거     Flow Logs: REJECT → 2·3 확정 / ACCEPT+불통 → 1 재심문
검증 완료: Step 2~4에서 1번(ACCEPT+불통)과 2번(REJECT) 케이스를 각각 목격 ✓
```

## 정리

```bash
bash cleanup.sh    # Flow Logs 중지 → 로그 그룹 삭제(비용!) → netlab/역할 정리
```
