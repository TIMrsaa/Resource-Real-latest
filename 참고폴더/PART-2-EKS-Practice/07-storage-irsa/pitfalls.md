# 흔한 함정 5선 — 07. Storage & IRSA

## 1. IRSA SA 어노테이션 오타로 영영 인증 실패

**증상**: Pod 의 AWS SDK 가 `Unable to locate credentials` 또는 `AccessDenied`.

**원인**: SA 의 `eks.amazonaws.com/role-arn` 값에 오타 — Role 이름 / Account ID 잘못.

**진단**:
```bash
kubectl get sa my-sa -o yaml | yq '.metadata.annotations'
aws iam get-role --role-name <role>      # 존재 확인
```

또는 `eksctl create iamserviceaccount` 명령을 다시 실행해 idempotent 하게 정상화.

---

## 2. Trust Policy 의 `:sub` 조건이 SA 이름과 불일치

**증상**: IAM Role 은 있는데 STS AssumeRoleWithWebIdentity 가 거부.

**원인**:
- SA 이름 또는 NS 가 변경되었는데 Trust 정책 미수정
- 다른 클러스터의 SA 로 시도 (issuer URL 다름)

**진단**:
```bash
ROLE=<role-name>
aws iam get-role --role-name $ROLE --query 'Role.AssumeRolePolicyDocument'
# Condition.StringEquals 의 :sub 값을 정확히 비교

# Pod 의 토큰 sub 디코딩
kubectl exec <pod> -- cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token \
  | awk -F. '{print $2}' | base64 -d | jq .sub
```

두 값이 정확히 일치해야 함. 일치 안 하면 Trust 수정.

---

## 3. EBS PVC 영영 Pending — IRSA 없는 EBS CSI

**증상**: PVC `Pending`, EBS CSI Controller 로그에 `UnauthorizedOperation`.

**원인**: ClusterConfig 에서 `wellKnownPolicies.ebsCSIController: true` 누락 → IRSA 셋업 안 됨.

**해결**:
```bash
eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=kube-system \
  --name=ebs-csi-controller-sa \
  --attach-policy-arn=arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --override-existing-serviceaccounts \
  --approve
```

addon 도 재설치/업데이트:
```bash
eksctl update addon --name aws-ebs-csi-driver --cluster eks-study \
  --service-account-role-arn $(aws iam get-role --role-name <role> --query 'Role.Arn' --output text)
```

---

## 4. Pod Identity 적용했는데 Pod 안에서 자격증명 못 가져옴

**증상**: Pod Identity association 만들었는데 `aws sts get-caller-identity` 가 실패.

**원인 후보**:
- `eks-pod-identity-agent` addon 미설치
- agent Pod이 떠있지 않은 노드에 워크로드가 배치됨 (DaemonSet 가 Ready 안됨)
- 옛 SDK (Pod Identity 미지원 버전)

**진단**:
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=eks-pod-identity-agent -o wide
aws eks list-pod-identity-associations --cluster-name eks-study
```

agent DaemonSet 에 Pod 가 모든 노드에 떠있는지 확인.

---

## 5. PVC 가 `WaitForFirstConsumer` 로 Pending — Pod 자체가 안 떠서

**증상**: PVC 가 `Pending`, Pod 도 `Pending`. 둘 다 서로 기다림.

**원인**: WaitForFirstConsumer 모드는 Pod 스케줄이 결정되어야 PV/EBS를 만듭니다. Pod 가 다른 이유로 스케줄링 못 되면 PVC 도 못 채워짐 — chicken-and-egg 처럼 보임.

**진단**:
```bash
kubectl describe pvc <pvc>            # "waiting for first consumer"
kubectl describe pod <pod>            # 진짜 원인 (이미지 pull, 노드 부족, taint 등)
```

**해결**: Pod 의 진짜 스케줄링 문제 해결. PVC 는 자동으로 따라옴.

데이터를 강제로 미리 만들고 싶으면 StorageClass 의 `volumeBindingMode: Immediate`. 단 Multi-AZ에서는 AZ 미스매치 위험.
