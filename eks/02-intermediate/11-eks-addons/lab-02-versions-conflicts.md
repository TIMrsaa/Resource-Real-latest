# Lab 02 — 충돌 해결 실험과 버전 업그레이드 절차

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. "내 수정이 사라지는" 현상 재현 (드디어 원리로)

```bash
# kubectl로 CoreDNS replicas를 직접 5로 (나쁜 습관의 연기)
kubectl scale deploy coredns -n kube-system --replicas=5
kubectl get deploy coredns -n kube-system    # 5

# 애드온 업데이트 트리거 (같은 설정 재적용으로 reconcile 유발)
aws eks update-addon --cluster-name $CLUSTER --region $AWS_REGION --addon-name coredns \
  --configuration-values '{"replicaCount":3}' --resolve-conflicts OVERWRITE
sleep 40; kubectl get deploy coredns -n kube-system    # 3으로 원복!
```

✅ **OVERWRITE의 실연**: EKS(필드 owner)가 자기 관리 필드를 회복했습니다. 07에서 예고한 미스터리의 종결 — kubectl 수정은 필드 소유권 싸움에서 집니다(k8s 24 SSA).

```bash
# 소유권 직접 확인 (k8s 24의 그 도구)
kubectl get deploy coredns -n kube-system --show-managed-fields -o yaml | grep -B2 "manager: eks" | head -6
```

## Step 2. PRESERVE의 자리 — 마이그레이션

자가 관리(헬름/수동) CoreDNS를 관리형 애드온으로 **편입**할 때, 기존 커스텀을 날리지 않으려면:

```bash
# (개념 — 이미 관리형이므로 출력만 이해)
# aws eks create-addon --addon-name coredns --resolve-conflicts PRESERVE ...
#   → 기존 클러스터 값들을 보존한 채 애드온 객체가 소유권을 인수
#   → 이후 점진적으로 configuration-values로 정식화
```

✅ PRESERVE = "일단 인수, 값은 보존" — 단 보존된 커스텀은 여전히 **비공식 상태**입니다. 인수 후 스키마로 옮기는 것까지가 마이그레이션.

## Step 3. 애드온 버전 업그레이드 — 안전 절차

```bash
# kube-proxy로 절차 시연 (가장 단순한 애드온)
CUR=$(aws eks describe-addon --cluster-name $CLUSTER --region $AWS_REGION --addon-name kube-proxy --query 'addon.addonVersion' --output text)
DEFAULT=$(aws eks describe-addon-versions --addon-name kube-proxy --kubernetes-version 1.36 --region $AWS_REGION \
  --query 'addons[0].addonVersions[?compatibilities[0].defaultVersion==`true`].addonVersion' --output text)
echo "현재: $CUR / 권장(default): $DEFAULT"

if [ "$CUR" != "$DEFAULT" ]; then
  aws eks update-addon --cluster-name $CLUSTER --region $AWS_REGION \
    --addon-name kube-proxy --addon-version $DEFAULT
  # 진행/검증
  watch -n5 "aws eks describe-addon --cluster-name $CLUSTER --region $AWS_REGION --addon-name kube-proxy --query 'addon.status' --output text"
fi
kubectl get ds kube-proxy -n kube-system    # 롤링 완료 확인
```

✅ 절차의 뼈대: **조회(default) → 한 번에 하나 → status 확인 → 실물 검증.** UPDATE_FAILED가 나면 describe-addon의 health.issues에 사유가 있습니다.

## Step 4. 실패 시나리오의 대응 (시나리오 연습)

```markdown
상황: vpc-cni를 latest로 올렸더니 status DEGRADED, 새 Pod이 IP를 못 받음
대응 절차:
1. describe-addon health.issues + aws-node 로그 (07의 ipamd 로그)
2. 호환 확인: 그 latest가 현 CP 버전 지원인가 (describe-addon-versions)
3. 롤백: update-addon --addon-version <직전 버전> (애드온은 버전 지정 롤백 가능!)
4. 사후: "latest 금지, default만" 규칙을 runbook에
```

✅ 애드온은 CP(비가역 — k8s 35)와 달리 **버전 지정 롤백이 됩니다** — 그래서 실험 부담이 상대적으로 작습니다. 그래도 운영은 default 기준.

## Step 5. 운영 체크리스트 (산출물)

```markdown
# 애드온 운영 수칙
- 설정: configuration-values만 (kubectl 직접 수정 금지 — 어차피 집니다)
- 버전: 대상 CP의 default 기준, 한 번에 하나, status+실물 검증
- CP 업그레이드 시: CP → 애드온(새 default) → 노드 순서에 편입 (21)
- 인벤토리: lab-01 Step 1 루프를 분기 점검에
- 신규 컴포넌트: 관리형 애드온 존재 여부부터 확인 (있으면 그쪽 우선)
```

## 정리

```bash
# 원복하려면 (선택): coredns replicas 2로
# aws eks update-addon --cluster-name $CLUSTER --region $AWS_REGION --addon-name coredns \
#   --configuration-values '{"replicaCount":2}'
echo "모듈 11 — 생성 리소스 없음 (설정 변경만)"
```
