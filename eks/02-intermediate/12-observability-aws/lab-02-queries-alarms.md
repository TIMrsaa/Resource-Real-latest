# Lab 02 — 묻고(Logs Insights), 울리고(알람), 아끼기(비용 통제)

수집(lab-01)은 절반입니다 — 관측성의 값어치는 **질문에 답할 때**, 그리고 **청구서가 통제될 때** 나옵니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. 사건 만들기 — 에러를 뿜는 Pod

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grumbler
  namespace: obs
  labels: { app: grumbler }
spec:
  replicas: 1
  selector:
    matchLabels: { app: grumbler }
  template:
    metadata:
      labels: { app: grumbler }
    spec:
      containers:
        - name: grumbler
          image: public.ecr.aws/docker/library/busybox:stable
          command: ["sh", "-c", 'while true; do echo "ERROR payment failed code=$((RANDOM%5))"; echo "INFO ok"; sleep 1; done']
EOF
kubectl rollout status deploy/grumbler -n obs
sleep 90    # CloudWatch 도착 대기
```

## Step 2. Logs Insights — "어느 Pod이 에러를 내나"

콘솔의 쿼리 편집기와 동일한 것을 CLI로 (start-query → get-query-results 2단):

```bash
QID=$(aws logs start-query --region $AWS_REGION \
  --log-group-name /aws/containerinsights/$CLUSTER/application \
  --start-time $(($(date +%s)-600)) --end-time $(date +%s) \
  --query-string 'fields @timestamp, log, kubernetes.pod_name
| filter kubernetes.namespace_name = "obs" and log like /ERROR/
| stats count(*) as errors by kubernetes.pod_name
| sort errors desc' \
  --query queryId --output text)
sleep 10
aws logs get-query-results --region $AWS_REGION --query-id $QID \
  --query 'results[][?field==`kubernetes.pod_name` || field==`errors`].value' --output table
```

예상: grumbler Pod이 수십 건, chatterbox는 0건. ✅ **"grep을 클러스터 전체·과거까지"** — 38의 진단 루틴이 시간 축을 얻었습니다. 쿼리의 `--start-time` 범위가 곧 스캔량(=비용)임도 기억.

## Step 3. 알람 — 사람이 보기 전에 기계가 봅니다

노드 CPU에 알람을 겁니다. 즉시 울리는 것을 보기 위해 임계값을 일부러 낮게(1%):

```bash
aws sns create-topic --name obs-lab-alerts --region $AWS_REGION
TOPIC=arn:aws:sns:$AWS_REGION:$(aws sts get-caller-identity --query Account --output text):obs-lab-alerts

aws cloudwatch put-metric-alarm --region $AWS_REGION \
  --alarm-name obs-lab-node-cpu \
  --namespace ContainerInsights --metric-name node_cpu_utilization \
  --dimensions Name=ClusterName,Value=$CLUSTER \
  --statistic Average --period 60 --evaluation-periods 2 \
  --threshold 1 --comparison-operator GreaterThanThreshold \
  --alarm-actions $TOPIC

# 상태기계 관찰: INSUFFICIENT_DATA → (2분 뒤) ALARM
watch -n15 "aws cloudwatch describe-alarms --alarm-names obs-lab-node-cpu \
  --region $AWS_REGION --query 'MetricAlarms[0].StateValue' --output text"
```

✅ OK/ALARM/INSUFFICIENT_DATA 상태 전이를 직접 봤습니다. 실전값으로 바꾸면(예: 80%, 5분×3회) 그대로 운영 알람 — 07의 ipamd, 11의 Degraded, k8s 37의 Pending 적체도 전부 [메트릭→알람→SNS] 같은 틀에 담습니다. (SNS 구독을 이메일로 걸면 발신까지 완성)

## Step 4. 비용 통제 ① — 보존 정책 (기본값은 무기한!)

```bash
# 현재 보존 설정 — retentionInDays가 비어 있으면 Never expire
aws logs describe-log-groups --log-group-name-prefix /aws/containerinsights/$CLUSTER \
  --region $AWS_REGION --query 'logGroups[].{name:logGroupName,retention:retentionInDays}' --output table

# 4형제 전부 7일 보존으로
for g in application dataplane host performance; do
  aws logs put-retention-policy --region $AWS_REGION \
    --log-group-name /aws/containerinsights/$CLUSTER/$g --retention-in-days 7
done
```

✅ 이 4줄이 없으면 로그는 **영원히** 쌓입니다 — 계정에서 가장 흔한 유령 비용.

## Step 5. 비용 통제 ② — 수집 필터 (안 보낼 자유)

시끄럽지만 가치 없는 Pod은 수집에서 뺍니다 — Fluent Bit kubernetes 필터의 exclude annotation:

```bash
kubectl patch deployment chatterbox -n obs --type=merge \
  -p '{"spec":{"template":{"metadata":{"annotations":{"fluentbit.io/exclude":"true"}}}}}'
kubectl rollout status deploy/chatterbox -n obs
sleep 90
aws logs tail /aws/containerinsights/$CLUSTER/application --region $AWS_REGION \
  --since 1m --filter-pattern chatterbox | head -3    # → (침묵)
```

예상: 새 로그 없음 — grumbler는 계속 옵니다. ✅ **수집량 통제는 Pod 단위부터 가능합니다.** 더 큰 칼은 애드온 configuration-values(11의 통로)로 수집 범위 자체를 조정하는 것 — 어느 쪽이든 "전부 수집이 기본, 편집은 우리 몫".

## Step 6. 비용 통제 ③ — 관측성을 관측 (수집량 알람)

```bash
aws cloudwatch put-metric-alarm --region $AWS_REGION \
  --alarm-name obs-lab-ingest-bytes \
  --namespace AWS/Logs --metric-name IncomingBytes \
  --dimensions Name=LogGroupName,Value=/aws/containerinsights/$CLUSTER/application \
  --statistic Sum --period 3600 --evaluation-periods 1 \
  --threshold 1000000000 --comparison-operator GreaterThanThreshold \
  --alarm-actions $TOPIC        # 시간당 1GB 초과 = 누가 디버그를 켰습니다
```

✅ "관측성 비용이 워크로드 비용을 넘는" 사고(guide의 경고)는 이 알람 하나로 조기 발견됩니다.

## Step 7. 중급 졸업 워크시트 (산출물)

```markdown
# 관측성 최소 운영 세트 — 우리 클러스터 체크리스트
- [ ] 애드온 ACTIVE + agent/fluent-bit DS 헬스 (lab-01)
- [ ] 로그 그룹 4형제 retention 설정 (기본 무기한 금지)
- [ ] 핵심 알람: node_cpu/memory, pod_number_of_container_restarts,
      cluster_failed_node_count, IncomingBytes(수집량)
- [ ] 수집 제외 규약: 어떤 워크로드에 fluentbit.io/exclude를 허용하나
- [ ] Insights 저장 쿼리: "ns별 에러 수", "Pod별 재시작", (13에서 추가: RPS/지연)
```

## 정리

```bash
bash cleanup.sh    # ★ 수집 중지까지 — 애드온을 지워야 과금이 멈춥니다
```
