# Lab 01 — 컨트롤 플레인 로깅과 Container Insights

> EKS에서 audit 로깅을 켜 05의 질문("누가?")을 관리형으로 답하고, Container Insights 애드온을 설치해 그 내부(CW agent + Fluent Bit)를 06의 눈으로 해부합니다.

## ⚠️ 비용 주의

EKS 클러스터(eks 파트의 것 재사용 권장) + CloudWatch ingest·저장 요금이 발생합니다. 각 단계 후 보존 설정, 마지막에 cleanup.sh 필수.

## 0. 준비 — 클러스터 확인

```bash
# eks 파트의 클러스터 재사용 (없으면 eks 파트 00-prerequisites 참고해 생성)
export CLUSTER=my-eks           # 자기 클러스터명
export REGION=ap-northeast-2
aws eks describe-cluster --name $CLUSTER --region $REGION \
  --query 'cluster.status' --output text
# ACTIVE
```

## 1. 컨트롤 플레인 로깅 — audit 켜기

```bash
# 현재 로깅 상태
aws eks describe-cluster --name $CLUSTER --region $REGION \
  --query 'cluster.logging.clusterLogging' --output json

# audit + authenticator 활성화 (실습 목적 최소 세트)
eksctl utils update-cluster-logging --cluster $CLUSTER --region $REGION \
  --enable-types audit,authenticator --approve

# 로그 그룹 생성 확인
aws logs describe-log-groups --region $REGION \
  --log-group-name-prefix "/aws/eks/$CLUSTER" \
  --query 'logGroups[].{name:logGroupName,retention:retentionInDays}'
# /aws/eks/<cluster>/cluster — retention: null (Never expire!) ← 즉시 고칠 것

# ★ 보존 설정 (비용 가드레일 — 실습은 1일)
aws logs put-retention-policy --region $REGION \
  --log-group-name "/aws/eks/$CLUSTER/cluster" --retention-in-days 1
```

## 2. audit로 "누가?"에 답하기 (05의 EKS판)

```bash
# 행위 생성: 시크릿 읽기 + 삭제
kubectl create secret generic db-pass --from-literal=p=hunter2
kubectl get secret db-pass -o yaml >/dev/null
kubectl delete secret db-pass
sleep 60   # 로그 전파 대기

# Logs Insights로 조회 (CLI)
QUERY_ID=$(aws logs start-query --region $REGION \
  --log-group-name "/aws/eks/$CLUSTER/cluster" \
  --start-time $(date -d '-10 minutes' +%s) --end-time $(date +%s) \
  --query-string 'filter @logStream like /audit/
    | filter objectRef.resource = "secrets" and objectRef.name = "db-pass"
    | fields @timestamp, user.username, verb
    | sort @timestamp desc | limit 10' \
  --query queryId --output text)
sleep 10
aws logs get-query-results --region $REGION --query-id $QUERY_ID \
  --query 'results[][?field==`user.username` || field==`verb`].value' --output text
# kubernetes-admin(또는 IAM 매핑 사용자)  get / delete
# ← ★ "누가 db-pass를 읽고 지웠나" — 관리형 audit로 즉답 (05의 완성)
```

**EKS 특유의 가치** — user.username에 IAM 매핑(aws-auth·access entries) 결과가 나옵니다. "어느 IAM 주체가 클러스터에서 무엇을 했나"가 이어지는 것 — eks 파트의 IAM 통합이 관측과 만나는 지점입니다. authenticator 로그는 "왜 forbidden인가"(매핑 실패) 조사에 씁니다.

## 3. Container Insights 애드온 설치

```bash
# IAM 권한(노드 롤에 CloudWatchAgentServerPolicy) 확인/부여 후:
aws eks create-addon --cluster-name $CLUSTER --region $REGION \
  --addon-name amazon-cloudwatch-observability

sleep 60
kubectl get pods -n amazon-cloudwatch
# cloudwatch-agent-xxxxx      (DaemonSet — 리소스 메트릭)
# fluent-bit-xxxxx            (DaemonSet — ★ 우리가 아는 그것!)
```

## 4. 애드온 해부 — 06의 눈으로

```bash
# Fluent Bit 설정을 읽어 봅니다
kubectl -n amazon-cloudwatch get configmap fluent-bit-config -o yaml | head -60
# [INPUT] tail /var/log/containers/*.log, multiline.parser cri   ← 06 그대로!
# [FILTER] kubernetes ...                                        ← 06 그대로!
# [OUTPUT] cloudwatch_logs, log_group_name /aws/containerinsights/...
```

**해부 결과** — 블랙박스가 아닙니다: 06에서 배운 tail·CRI 파서·kubernetes 필터가 그대로 있고, OUTPUT만 cloudwatch_logs 플러그인입니다. 로그 그룹 구조도 확인:

```bash
aws logs describe-log-groups --region $REGION \
  --log-group-name-prefix "/aws/containerinsights/$CLUSTER" \
  --query 'logGroups[].logGroupName'
# .../application   ← 앱 컨테이너 stdout
# .../dataplane     ← kubelet·containerd (02의 데몬 로그)
# .../host          ← 노드 로그
# ★ 각각 retention 설정! (기본 Never expire)
for g in application dataplane host performance; do
  aws logs put-retention-policy --region $REGION \
    --log-group-name "/aws/containerinsights/$CLUSTER/$g" --retention-in-days 1 2>/dev/null || true
done
```

## 5. Container Insights 메트릭·화면 확인

```bash
# 테스트 앱 배포 후 메트릭 확인
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels: { app: web }
spec:
  replicas: 2
  selector:
    matchLabels: { app: web }
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
        - name: nginx
          image: nginx
EOF
sleep 120

aws cloudwatch list-metrics --region $REGION --namespace ContainerInsights \
  --dimensions Name=ClusterName,Value=$CLUSTER \
  --query 'Metrics[?MetricName==`pod_cpu_utilization`] | [0]'
# pod_cpu_utilization (디멘션: ClusterName·Namespace·PodName)
# ← 08의 cAdvisor 역할을 CW agent가 — CW 콘솔 Container Insights에서
#   클러스터→노드→Pod 드릴다운 대시보드 자동 제공 (09의 L1~L3 기본판)
```

**대응 정리** — 콘솔에서 Container Insights 화면을 열어 보라: 리소스(USE 계열) 중심의 자동 대시보드입니다. RED(서비스 관점)는 앱 메트릭이 필요하므로 여기 없습니다 — 그것이 AMP(14)+ADOT(16)의 자리입니다.

## 6. 정리 (일부 — 전체는 cleanup.sh)

```bash
kubectl delete deployment web
```

## 정리

- 컨트롤 플레인 로깅: eksctl 한 줄 → audit가 CW로 — "누가?"를 Logs Insights로 즉답 (user에 IAM 매핑!)
- **retention 설정이 첫 행동** — 기본 Never expire는 비용 방치
- Container Insights = CW agent(리소스 메트릭) + Fluent Bit(로그) — 06 지식으로 설정을 읽고 커스텀 가능
- 로그 그룹 3분류(application/dataplane/host) — 각각 보존 관리
- **★ 관리형이어도 부품은 아는 것(Fluent Bit)입니다 — 해부할 수 있으면 통제(비용·커스텀)할 수 있습니다**
