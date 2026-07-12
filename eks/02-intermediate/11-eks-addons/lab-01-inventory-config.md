# Lab 01 — 인벤토리, 스키마, 선언적 설정

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. 인벤토리 — 내 클러스터의 부품 목록

```bash
aws eks list-addons --cluster-name $CLUSTER --region $AWS_REGION
for A in $(aws eks list-addons --cluster-name $CLUSTER --region $AWS_REGION --query 'addons[]' --output text); do
  aws eks describe-addon --cluster-name $CLUSTER --region $AWS_REGION --addon-name $A \
    --query 'addon.{name:addonName,version:addonVersion,status:status}' --output text
done
```

✅ 07~10에서 설치해온 것들이 한 표로 — **이 표가 업그레이드 계획(21)의 입력**입니다. status가 전부 ACTIVE인지도 점검(아니면 그 자체가 조사 대상).

## Step 2. 호환 매트릭스 조회

```bash
# 현 K8s 버전에서 coredns의 선택지와 default
aws eks describe-addon-versions --addon-name coredns --kubernetes-version 1.36 --region $AWS_REGION \
  --query 'addons[0].addonVersions[0:5].{v:addonVersion,default:compatibilities[0].defaultVersion}' --output table
# 다음 버전(1.37) 기준으로도 — 업그레이드 사전 조사
aws eks describe-addon-versions --addon-name coredns --kubernetes-version 1.37 --region $AWS_REGION \
  --query 'addons[0].addonVersions[0:3].[addonVersion]' --output text 2>/dev/null | head -3
```

✅ "다음 CP 버전에서 이 애드온의 default는 무엇인가"를 **업그레이드 전에** 묻는 루틴 — k8s 35 preflight의 애드온 항목이 이 명령입니다.

## Step 3. 스키마 읽기 — 공식 옵션 화면

```bash
V=$(aws eks describe-addon --cluster-name $CLUSTER --region $AWS_REGION --addon-name coredns \
  --query 'addon.addonVersion' --output text)
aws eks describe-addon-configuration --addon-name coredns --addon-version $V --region $AWS_REGION \
  --query 'configurationSchema' --output text | python3 -m json.tool | grep -E '"(replicaCount|resources|autoScaling|tolerations)"' 
```

✅ replicaCount, resources, autoScaling... — **바꿀 수 있는 것의 전체 목록**이 스키마다. k8s 16에서 "CoreDNS 기본 2 replicas가 대규모의 화근"이라 한 그 다이얼이 여기 있습니다.

## Step 4. 선언적 설정 — CoreDNS replicas 3으로

```bash
kubectl get deploy coredns -n kube-system    # 현재 2
aws eks update-addon --cluster-name $CLUSTER --region $AWS_REGION --addon-name coredns \
  --configuration-values '{"replicaCount":3}' --resolve-conflicts OVERWRITE
# 진행 관찰
aws eks describe-addon --cluster-name $CLUSTER --region $AWS_REGION --addon-name coredns \
  --query 'addon.status'
sleep 30; kubectl get deploy coredns -n kube-system    # 3!
```

✅ kubectl scale이 아니라 **애드온 설정**으로 — 이래야 다음 애드온 업데이트에도 3이 유지됩니다(진실의 원천). 검증 실패도 체험:

```bash
aws eks update-addon --cluster-name $CLUSTER --region $AWS_REGION --addon-name coredns \
  --configuration-values '{"replicaCounts":3}' 2>&1 | tail -2    # 오타 키 → 거부!
```

✅ 스키마 검증이 오타를 **시끄럽게** 거부 — 조용히 무시되는 설정(k8s의 unknown field 이슈)보다 운영 친화적.

## Step 5. ClusterConfig에 반영 (IaC 마감)

eks 02에서 만든 `cluster.yaml`의 addons 섹션을 현실과 동기화:

```yaml
addons:
- name: coredns
  configurationValues: |
    replicaCount: 3
- { name: vpc-cni, configurationValues: "{\"env\":{\"ENABLE_PREFIX_DELEGATION\":\"true\"}}" }
- { name: kube-proxy }
- { name: eks-pod-identity-agent }
- { name: aws-ebs-csi-driver }
```

✅ **클러스터 부품 구성이 Git 한 파일로** — DR(24)에서 이 파일이 부품까지 복원합니다.

## 정리

설정 변경(replicas 3)은 유지해도 무방(정당한 운영 값). 원복하려면 lab-02 후 cleanup 참고.
