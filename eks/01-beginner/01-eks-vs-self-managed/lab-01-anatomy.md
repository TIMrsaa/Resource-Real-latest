# Lab 01 — 내 클러스터 해부: AWS API로 경계선 확인

> k8s 파트의 공유 클러스터(k8s-study)를 **AWS 쪽에서** 들여다봅니다. (없으면 k8s 파트 모듈 01의 생성 절차로 — 또는 eks 모듈 02에서 새로 만들며 배웁니다)

```bash
export AWS_REGION=ap-northeast-2
export CLUSTER=k8s-study
```

## Step 1. 클러스터 객체 — AWS가 보는 내 클러스터

```bash
aws eks describe-cluster --name $CLUSTER --region $AWS_REGION \
  --query 'cluster.{version:version,status:status,endpoint:endpoint,platformVersion:platformVersion,supportType:upgradePolicy.supportType}'
```

예상 출력:
```json
{
  "version": "1.36",
  "status": "ACTIVE",
  "endpoint": "https://XXXX.gr7.ap-northeast-2.eks.amazonaws.com",
  "platformVersion": "eks.N",
  "supportType": "STANDARD"
}
```

✅ 읽는 법: `endpoint`가 k8s 파트 내내 kubectl이 때리던 그 API 서버입니다(kubeconfig와 대조: `kubectl cluster-info`). `platformVersion`은 같은 1.36 안에서 AWS가 control plane에 패치를 넣는 단위 — **우리가 안 올려도 AWS가 올립니다**(경계선 너머의 일). `supportType: STANDARD`가 EXTENDED가 되는 순간 6배 과금입니다.

## Step 2. 보이지 않는 것들의 증거 — etcd와 컴포넌트

```bash
# k8s 파트 습관대로 control plane Pod를 찾아보면...
kubectl get pods -n kube-system | grep -E "etcd|apiserver|scheduler|controller-manager" || echo "없음!"
kubectl get nodes    # 워커 노드만 보입니다
```

✅ kubeadm 클러스터(k8s 41의 kind)에선 보이던 control plane Pod들이 **없습니다** — AWS 계정 어딘가의 전용 인프라에서 돌고, 우리에겐 endpoint만 노출됩니다. 이것이 경계선의 실물.

```bash
# 그래도 그들의 "출력"은 받을 수 있습니다 — control plane 로그 (k8s 21 lab-02에서 켰던 것)
aws eks describe-cluster --name $CLUSTER --region $AWS_REGION \
  --query 'cluster.logging.clusterLogging[?enabled==`true`].types' --output text
```

## Step 3. 네트워크 경계 — 엔드포인트 노출 점검

```bash
aws eks describe-cluster --name $CLUSTER --region $AWS_REGION \
  --query 'cluster.resourcesVpcConfig.{publicAccess:endpointPublicAccess,privateAccess:endpointPrivateAccess,publicCidrs:publicAccessCidrs}'
```

예상: 학습 클러스터는 `publicAccess: true` + `0.0.0.0/0`일 가능성이 큽니다.

✅ **공유 책임의 내 몫 1호 발견**: API 서버가 전 세계에 열려 있습니다(인증은 필요하지만 노출 자체가 공격면). 운영 정석은 public CIDR 제한 또는 private 전용 — 모듈 25에서 잠급니다. 지금은 "내 책임 영역임을 인지"까지.

## Step 4. 노드의 정체 — 회색지대 확인

```bash
aws eks list-nodegroups --cluster-name $CLUSTER --region $AWS_REGION
NG=$(aws eks list-nodegroups --cluster-name $CLUSTER --region $AWS_REGION --query 'nodegroups[0]' --output text)
aws eks describe-nodegroup --cluster-name $CLUSTER --nodegroup-name $NG --region $AWS_REGION \
  --query 'nodegroup.{type:amiType,instance:instanceTypes,version:version,health:health.issues}'
# 그 노드그룹의 실체는 내 계정의 EC2입니다:
aws ec2 describe-instances --filters "Name=tag:eks:nodegroup-name,Values=$NG" --region $AWS_REGION \
  --query 'Reservations[].Instances[].{id:InstanceId,type:InstanceType,state:State.Name}' --output table
```

✅ **회색지대의 실물**: 노드그룹이라는 EKS 객체(AWS가 수명주기 관리)가 내 계정의 EC2(내가 요금 냄)를 거느립니다. EC2 콘솔에서 보이고 내 비용에 잡히지만, 직접 terminate하면 EKS가 다시 만듭니다 — 수명주기의 주인이 누군지 보여주는 동작.

## Step 5. OIDC — k8s와 IAM의 다리 (모듈 09 예고)

```bash
aws eks describe-cluster --name $CLUSTER --region $AWS_REGION \
  --query 'cluster.identity.oidc.issuer' --output text
```

✅ 이 issuer URL이 "Pod의 ServiceAccount 토큰(k8s 11)을 AWS IAM이 신뢰하게 만드는" 다리입니다 — IRSA/Pod Identity(모듈 09)의 뿌리. 지금은 존재만 확인.

## Step 6. 경계선 지도 완성 (산출물)

```markdown
# 내 클러스터 경계선 지도 — $CLUSTER
- API endpoint: ___ (public: ___ ← 모듈 25에서 잠글 것)
- 버전: 1.36 / platform: eks.__ / 지원: STANDARD (연장 진입 예정일: 버전 캘린더 확인 → ____)
- control plane 로그: ___ (꺼져 있으면 비용 vs 가시성 트레이드오프 메모)
- 노드그룹: __ (AMI: ___, 인스턴스: ___) → EC2 ID: ___
- OIDC issuer: ___ (모듈 09에서 사용)
내 책임 체크: IP 계획(07/16), IAM(09), 업그레이드 달력(21), 비용(lab-02)
```
