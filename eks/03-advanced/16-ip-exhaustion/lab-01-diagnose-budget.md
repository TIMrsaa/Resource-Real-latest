# Lab 01 — 우리 클러스터의 IP 가계부 쓰기

고갈 대응의 절반은 도구가 아니라 **회계**입니다. 실측으로 소진 방정식을 채우고, "몇 Pod 남았나"에 숫자로 답한 뒤, 마르기 전에 울릴 장치를 답니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. 공급 — 서브넷별 잔여 IP 실측

```bash
# 클러스터가 쓰는 서브넷들
SUBNETS=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION \
  --query 'cluster.resourcesVpcConfig.subnetIds' --output text)

aws ec2 describe-subnets --subnet-ids $SUBNETS --region $AWS_REGION \
  --query 'Subnets[].{az:AvailabilityZone,cidr:CidrBlock,free:AvailableIpAddressCount}' --output table
```

기록하세요 — 특히 **min(free)**. theory §1: 고갈은 합계가 아니라 가장 마른 AZ에서 시작됩니다.

## Step 2. 수요 — 노드가 실제로 잡고 있는 IP (warm 포함)

```bash
# 노드(ENI)들이 선점한 IP 수 vs 실제 Pod 수
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  IID=$(kubectl get node $node -o jsonpath='{.spec.providerID}' | awk -F/ '{print $NF}')
  TAKEN=$(aws ec2 describe-network-interfaces --region $AWS_REGION \
    --filters Name=attachment.instance-id,Values=$IID \
    --query 'length(NetworkInterfaces[].PrivateIpAddresses[])' --output text)
  PODS=$(kubectl get pods -A --field-selector spec.nodeName=$node -o json \
    | python3 -c "import json,sys; ps=json.load(sys.stdin)['items']; print(len([p for p in ps if not p['spec'].get('hostNetwork')]))")
  echo "$node: 선점 IP=$TAKEN / 실사용 Pod=$PODS  → warm 예약 ≈ $((TAKEN-PODS-1))"
done
```

✅ **선점 − 실사용의 간극이 warm pool의 실체**입니다 (07의 이론이 청구서가 되는 순간). 노드 수가 늘면 이 간극도 함께 늡니다.

## Step 3. 설정 — 지금 warm 정책은 무엇인가

```bash
kubectl get ds aws-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].env}' \
  | python3 -m json.tool | grep -B1 -A2 -E "WARM|MINIMUM|PREFIX"
```

기본값(WARM_ENI_TARGET=1, prefix off)이라면 Step 2의 간극이 설명됩니다. (조정은 클러스터 전역 영향 — 여기선 읽기만, 손잡이의 의미는 theory §2.)

## Step 4. 방정식 완성 — 잔여 Pod 예산 계산기

```bash
cat > ip-budget.sh <<'EOF'
#!/usr/bin/env bash
# 잔여 Pod 예산 ≈ min(AZ별 free) - (신규 노드가 붙을 때의 warm 선점 고려는 보수적으로 ENI 1장=10~15)
set -euo pipefail
REGION=${1:-ap-northeast-2}; CLUSTER=${2:-k8s-study}
SUBNETS=$(aws eks describe-cluster --name $CLUSTER --region $REGION \
  --query 'cluster.resourcesVpcConfig.subnetIds' --output text)
aws ec2 describe-subnets --subnet-ids $SUBNETS --region $REGION \
  --query 'Subnets[].{az:AvailabilityZone,free:AvailableIpAddressCount}' --output text \
  | sort -k2 -n | awk '{print; if(NR==1){min=$2; az=$1}} END {
      print "----"
      print "병목 AZ:", az, "잔여:", min
      print "보수적 Pod 예산(노드 증설분 warm 감안 -15/node):", min-15 }'
EOF
chmod +x ip-budget.sh && ./ip-budget.sh $AWS_REGION $CLUSTER
```

이 숫자를 최근 한 달의 Pod 증가 추세와 나누면 **"몇 달 남았나"** 가 나옵니다 — guide의 결정 트리 입력값.

## Step 5. 마르기 전에 울리기 (12의 틀 재사용)

서브넷 잔여 IP는 기본 CloudWatch 메트릭이 없습니다 — 두 가지 현실적 장치:

```bash
# ① CNI 자체 메트릭: aws-node의 프로메테우스 포트(61678)에 이미 있습니다
kubectl get ds aws-node -n kube-system -o jsonpath='{.spec.template.metadata.annotations}'
#   awscni_total_ip_addresses / awscni_assigned_ip_addresses
#   → 15의 Prometheus가 있다면 즉시 수집 가능: (assigned/total) > 0.8 알람
#   → CloudWatch로 보내려면 cni-metrics-helper (공식 부속)

# ② 예산 스크립트의 정기 실행: Step 4를 CronJob(k8s 20)으로 + 임계 미만 시 SNS
```

✅ 설계 산출물로 남깁니다:

```markdown
# IP 가계부 — YYYY-MM-DD
- 공급: AZ-a __ / AZ-b __ / AZ-c __ (min: __)
- 수요: 노드 __대, 선점 __ IP (실사용 __ + warm __)
- 예산: 약 __ Pod / 추세 대비 약 __개월
- 결정(트리): [ ] 알람만  [ ] warm 튜닝  [ ] prefix  [ ] secondary CIDR(→lab-02)  [ ] 다음 클러스터 IPv6
- 알람: assigned/total 80% (Prometheus) — 담당: __
```

## 정리

생성 리소스 없음 (읽기 전용 + 스크립트 파일). lab-02로.
