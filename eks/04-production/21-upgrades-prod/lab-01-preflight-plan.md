# Lab 01 — 실클러스터 preflight와 업그레이드 계획서

우리 클러스터(k8s-study)를 대상으로 preflight 전체를 **실제로** 수행하고, 그 결과를 계획서 양식에 채웁니다. (CP 업그레이드 실행 자체는 선택 — 마지막 Step 참조)

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. 현황 조사 — 네 표면의 버전을 한 표에

```bash
echo "=== Control Plane ==="
aws eks describe-cluster --name $CLUSTER --region $AWS_REGION --query 'cluster.version' --output text

echo "=== 노드그룹들 ==="
for ng in $(aws eks list-nodegroups --cluster-name $CLUSTER --region $AWS_REGION --query 'nodegroups' --output text); do
  aws eks describe-nodegroup --cluster-name $CLUSTER --region $AWS_REGION --nodegroup-name $ng \
    --query 'nodegroup.{name:nodegroupName,version:version,ami:releaseVersion}' --output table
done

echo "=== 노드 실물 (kubelet skew 확인) ==="
kubectl get nodes -o custom-columns='NAME:.metadata.name,KUBELET:.status.nodeInfo.kubeletVersion'

echo "=== 애드온 ==="
aws eks list-addons --cluster-name $CLUSTER --region $AWS_REGION --output table
for a in $(aws eks list-addons --cluster-name $CLUSTER --region $AWS_REGION --query 'addons' --output text); do
  printf "%-40s " $a
  aws eks describe-addon --cluster-name $CLUSTER --region $AWS_REGION --addon-name $a --query 'addon.addonVersion' --output text
done
```

## Step 2. 게이트 G1 — insights

```bash
aws eks list-insights --cluster-name $CLUSTER --region $AWS_REGION \
  --filter categories=UPGRADE_READINESS \
  --query 'insights[].{name:name,status:insightStatus.status,reason:insightStatus.reason}' --output table

# ERROR/WARNING이 있다면 근거까지
for id in $(aws eks list-insights --cluster-name $CLUSTER --region $AWS_REGION \
  --query "insights[?insightStatus.status!='PASSING'].id" --output text); do
  aws eks describe-insight --cluster-name $CLUSTER --region $AWS_REGION --id $id \
    --query 'insight.{name:name,recommendation:recommendation}' --output json
done
```

판정 규칙 그대로: **ERROR 1건 = 중단.** WARNING은 계획서의 "수용 사유" 칸으로.

## Step 3. 게이트 G2~G4 — 정적 스캔·PDB·용량

```bash
# G2: Pluto (35 lab-01의 그 절차 — 저장소/차트 대상)
pluto detect-helm 2>/dev/null | head || echo "(pluto 미설치면 35 참조)"

# G3: PDB 데드락 후보 (자동화 스크립트로 — 사람이 까먹는 1순위)
kubectl get pdb -A -o json | python3 -c "
import json,sys
bad=[f\"{p['metadata']['namespace']}/{p['metadata']['name']}\"
     for p in json.load(sys.stdin)['items']
     if p.get('status',{}).get('disruptionsAllowed',0)==0]
print('PDB 데드락 후보:', bad if bad else '없음')"

# G4: 용량 여유 — drain 중 Pod가 옮겨갈 자리 (요청량 합 vs 할당 가능량)
kubectl describe nodes | grep -A5 "Allocated resources" | grep -E "cpu|memory" | head -8
```

## Step 4. 목표 버전의 애드온 좌표 확보

```bash
CUR=$(aws eks describe-cluster --name $CLUSTER --region $AWS_REGION --query 'cluster.version' --output text)
TARGET=$(echo $CUR | awk -F. '{print $1"."$2+1}')
echo "현재 $CUR → 목표 $TARGET"

for a in vpc-cni coredns kube-proxy; do
  printf "%-12s → " $a
  aws eks describe-addon-versions --addon-name $a --kubernetes-version $TARGET --region $AWS_REGION \
    --query 'addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion' --output text
done
```

## Step 5. 계획서 작성 (이 모듈의 산출물)

```markdown
# 업그레이드 계획서 — k8s-study: 1.36 → 1.37 (작성: __ / 실행 창: __)
## 현황 (Step 1의 표)
CP __ / NG workers __ / kubelet __ / 애드온: vpc-cni __, coredns __, kube-proxy __
## 게이트 판정
- [ ] insights ERROR 0 (WARNING 수용 사유: __)
- [ ] Pluto 0건 / PDB 데드락 0건 / Velero 백업 __시각 (36)
- [ ] 용량 여유 ≥ 노드 1대분 (drain 이주 공간)
- [ ] 이벤트 캘린더 무충돌 확인
## 실행 (표면별 — 각 단계 후 검증 명령 포함)
1. CP: aws eks update-cluster-version --kubernetes-version 1.37  (화요일 오전 / 비가역!)
   검증: describe-cluster status ACTIVE + kubectl get --raw /version
2. 애드온: Step 4의 default 버전으로 update-addon (vpc-cni→coredns→kube-proxy)
   검증: describe-addon ACTIVE + 각 DS/Deploy 롤링 완료
3. 노드: [전략 선택] 관리형 롤링 (updateConfig maxUnavailable=1) — 목요일
   예상 시간: 노드 _대 × drain ~_분 = _
   검증: get nodes 버전 일치 + 앱 golden signal + 관측 스택 헬스(12)
## 롤백 조건과 수단
- CP: 불가 — 그래서 게이트 / 애드온: 직전 버전 지정 재설치(11) / 노드: 구 releaseVersion 재롤링
- 중단 판단 기준: 오류율 __% 초과 또는 P1 장애 발생 시 노드 단계 일시정지(창 종료)
```

## Step 6. (선택) 실제 실행

클러스터가 최신-1 이하이고 공유자 합의가 있다면 계획서대로 실행해보세요 — CP 업그레이드는 20~40분, 그동안 `kubectl`이 계속 동작함(HA 무중단)을 관찰하는 것 자체가 학습입니다:

```bash
# aws eks update-cluster-version --name $CLUSTER --region $AWS_REGION --kubernetes-version $TARGET
# watch -n30 "aws eks describe-cluster --name $CLUSTER --region $AWS_REGION --query 'cluster.status' --output text"
```

## 정리

생성 리소스 없음. lab-02에서 노드 전략을 실연합니다.
