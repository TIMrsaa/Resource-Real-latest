# AWS CLI 치트시트 (EKS 운영자용)

> 증상은 kubectl에서, 원인은 여기서 — 26의 계층 심문에 필요한 명령들.

## 진단 3종 (26)

```bash
export R=ap-northeast-2 C=k8s-study

# ① IP 예산 — AZ별 최솟값이 병목 (16)
SUBNETS=$(aws eks describe-cluster --name $C --region $R --query 'cluster.resourcesVpcConfig.subnetIds' --output text)
aws ec2 describe-subnets --subnet-ids $SUBNETS --region $R \
  --query 'Subnets[].{az:AvailabilityZone,free:AvailableIpAddressCount}' --output table

# ② 업그레이드 차단 요소 (21)
aws eks list-insights --cluster-name $C --region $R --filter categories=UPGRADE_READINESS \
  --query 'insights[].{name:name,status:insightStatus.status}' --output table

# ③ 애드온 건강 (11)
aws eks describe-addon --cluster-name $C --region $R --addon-name vpc-cni \
  --query 'addon.{status:status,version:addonVersion,issues:health.issues}'
```

## 클러스터·노드

```bash
aws eks describe-cluster --name $C --region $R --query 'cluster.{v:version,status:status,endpoint:endpoint}'
aws eks list-nodegroups --cluster-name $C --region $R
aws eks describe-nodegroup --cluster-name $C --region $R --nodegroup-name workers \
  --query 'nodegroup.{version:version,ami:releaseVersion,status:status}'

# 애드온 버전 좌표 (11·21) — latest가 아니라 default!
aws eks describe-addon-versions --addon-name coredns --kubernetes-version 1.36 --region $R \
  --query 'addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion' --output text
```

## 고아 사냥 (22)

```bash
# 미부착 EBS
aws ec2 describe-volumes --region $R --filters Name=status,Values=available \
  --query 'Volumes[].{id:VolumeId,GiB:Size}' --output table

# 유령 LB (클러스터에 주인이 없는데 살아 있는 것 — 14)
aws elbv2 describe-load-balancers --region $R --query 'LoadBalancers[].LoadBalancerName' --output text

# 무기한 보존 로그 그룹 (12)
aws logs describe-log-groups --region $R --query 'logGroups[?retentionInDays==null].logGroupName' --output text

# velero 스냅샷 잔재 (36·24)
aws ec2 describe-snapshots --owner-ids self --region $R \
  --filters "Name=tag-key,Values=velero.io/backup" --query 'Snapshots[].SnapshotId' --output text
```

## 보안 (25)

```bash
# IMDS 차단 — 이 파트의 가장 중요한 한 줄
aws ec2 modify-instance-metadata-options --region $R --instance-id <i-xxx> \
  --http-put-response-hop-limit 1 --http-tokens required --http-endpoint enabled

# 노드 역할의 정책 감사
aws iam list-attached-role-policies --role-name <NodeRole>

# Secrets Manager
aws secretsmanager get-secret-value --region $R --secret-id app/db --query SecretString --output text
```

## 관측 (12·18)

```bash
# 로그 실시간
aws logs tail /aws/containerinsights/$C/application --region $R --since 5m --follow

# Logs Insights 쿼리 (2단)
QID=$(aws logs start-query --region $R --log-group-name /aws/containerinsights/$C/application \
  --start-time $(($(date +%s)-900)) --end-time $(date +%s) \
  --query-string 'fields @timestamp, log | filter log like /ERROR/ | limit 20' --query queryId --output text)
sleep 8; aws logs get-query-results --region $R --query-id $QID --output table

# 보존 정책 (기본 무기한!)
aws logs put-retention-policy --region $R --log-group-name <name> --retention-in-days 14
```

## 트래픽 (14)

```bash
aws elbv2 describe-target-groups --region $R --query 'TargetGroups[].{n:TargetGroupName,arn:TargetGroupArn}' --output table
aws elbv2 describe-target-health --region $R --target-group-arn <arn> \
  --query 'TargetHealthDescriptions[].{id:Target.Id,state:TargetHealth.State,reason:TargetHealth.Reason}' --output table

aws elbv2 describe-load-balancer-attributes --region $R --load-balancer-arn <arn> \
  --query "Attributes[?Key=='idle_timeout.timeout_seconds']"
```

## 비용 (22)

```bash
# 이번 달 서비스별 (숨은 3대장을 여기서 봅니다)
aws ce get-cost-and-usage --time-period Start=$(date +%Y-%m-01),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY --metrics UnblendedCost --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[0].Groups[?Metrics.UnblendedCost.Amount>`1`].{svc:Keys[0],usd:Metrics.UnblendedCost.Amount}' --output table
```

## 안전 습관

- `--dry-run`(지원 시), `--query`로 필요한 필드만, `--output table`로 사람이 읽게
- 파괴적 명령 전 `describe`로 대상 확인 — 특히 `delete-cluster`, `rb --force`
- 계정/리전 확인: `aws sts get-caller-identity` + `echo $AWS_REGION` (사고의 절반은 잘못된 컨텍스트)
