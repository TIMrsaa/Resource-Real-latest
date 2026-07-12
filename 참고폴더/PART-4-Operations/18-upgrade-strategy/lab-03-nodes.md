# Lab 03 — Addon + 노드 그룹 업그레이드

> **🌱 핵심 개념 미리보기**
> - **EKS Addon**: AWS 가 관리해 주는 핵심 컴포넌트 (vpc-cni, coredns, kube-proxy, ebs-csi). 버전을 명시적으로 올려야 함.
> - **Managed Node Group 업그레이드**: ASG surge → 새 AMI 노드 추가 → 옛 노드 cordon/drain → 종료의 4단계.
> - **Karpenter Drift**: AMI alias 가 바뀌거나 NodePool spec 이 바뀌면 기존 노드를 자동 교체. 노드 그룹 업그레이드 대체.
> - **AL2023 vs AL2**: EKS 1.30+ 부터 AL2023 권장 (AL2 는 EOL 일정 있음). AMI alias 로 추적.
> - **Surge Strategy**: 동시에 띄울 새 노드 수. 빠르지만 비용 높음 vs 천천히/안전하게의 트레이드오프.

## 1. Addon 업그레이드

```bash
TARGET=1.31

for addon in vpc-cni coredns kube-proxy aws-ebs-csi-driver; do
  LATEST=$(eksctl utils describe-addon-versions --kubernetes-version $TARGET --name $addon \
    --query 'Addons[0].AddonVersions[0].AddonVersion' --output text)
  echo "→ Updating $addon to $LATEST"
  eksctl update addon --name $addon --version $LATEST --cluster eks-study \
    --region ap-northeast-2 --force
done
```

각 addon 약 1~2분 소요. coredns / kube-proxy 가 DaemonSet/Deployment 라 점진 갱신.

> **🧠 `--force` 의 의미와 위험**
> 보통 EKS 는 사용자가 직접 수정한 addon (예: coredns ConfigMap 의 커스텀 도메인) 을 덮어쓰지 않으려 conflict 시 업그레이드 거부.
> `--force` = "내 수정사항 덮어써도 된다" 선언. 운영에선 위험 — 커스텀 설정 백업 후 명시적 재적용 권장.
> 또 다른 옵션: `--resolve-conflicts PRESERVE` 로 사용자 수정사항 보존하면서 가능한 부분만 업그레이드.

## 2. addon 업그레이드 검증

```bash
eksctl get addon --cluster eks-study
```

기대: 모든 addon `STATUS: ACTIVE`, version 이 새것.

```bash
# 시스템 Pod 들 모두 Ready
kubectl get pods -n kube-system | grep -vE 'Running|Completed'
```

## 3. 노드 그룹 업그레이드

### 3.1 Managed Node Group

```bash
eksctl upgrade nodegroup --cluster eks-study --name workers
# 또는 콘솔: 노드 그룹 → Update version
```

진행:
- 새 launch template 생성 (최신 EKS-optimized AMI 1.31)
- ASG surge: 새 노드 추가
- 옛 노드 cordon / drain
- 옛 인스턴스 종료

watch:
```bash
watch -n5 'kubectl get nodes -o jsonpath="{range .items[*]}{.metadata.name}={.status.nodeInfo.kubeletVersion}{\"\n\"}{end}"'
```

기대: 점진적으로 v1.31.x 로 교체.

소요: 노드 수 × 약 5분.

> **🧠 Managed Node Group 업그레이드의 4단계 자세히**
> 1. **Setup**: 새 AMI 로 Launch Template 새 버전 생성. ASG 의 desired = 기존 + maxUnavailable 만큼 증가.
> 2. **Scale up**: 새 노드 부팅. kubelet 등록까지 ~3분.
> 3. **Upgrade**: 옛 노드 하나씩 `cordon` (스케줄링 차단) + `drain` (Pod evict). PDB 가 막으면 최대 1시간 대기.
> 4. **Scale down**: 옛 노드 종료, ASG desired 원복.
>
> 실패 시 자동 롤백 X — `eksctl` 로 다시 옛 버전 nodegroup 만들어 수동 복구.

### 3.2 Karpenter 노드 (만약 떠있으면)

EC2NodeClass 의 amiFamily 가 `AL2023` + alias `al2023@latest` 면 자동 Drift 발생.

수동 트리거:
```bash
# AMI alias 업데이트 (예시)
kubectl patch ec2nodeclass default --type=merge -p '{"spec":{"amiSelectorTerms":[{"alias":"al2023@latest"}]}}'
# (이미 latest 면 변화 없음)
```

또는 강제:
```bash
# 모든 Karpenter 노드 drift 마크
kubectl annotate nodes -l managed-by=karpenter karpenter.sh/disruption-=
```

watch:
```bash
watch -n5 'kubectl get nodeclaims -L karpenter.sh/drifted'
```

> **🧠 Karpenter Drift 가 노드 그룹 업그레이드보다 좋은 점**
> - **선언적**: "AMI alias 가 latest 면 자동" — 매번 수동 트리거 불필요.
> - **세밀한 disruption budget**: 시간대/요일별로 한 번에 교체할 노드 수 제한.
> - **빠른 교체**: ASG 의 lifecycle hook 없이 곧장 NodeClaim 단위로 교체.
> - **Spot 친화**: 인스턴스 회수 알림 + drift 통합 처리.
>
> 단점: NodePool/EC2NodeClass 의 `disruption.budgets` 설정 안 하면 한꺼번에 다 교체될 수 있음 — 운영 시 필수 설정.

## 4. PDB 영향 확인

업그레이드 중 PDB 가 막아 stuck 되면:
```bash
kubectl get pods -A -o jsonpath='{range .items[?(@.status.phase!="Running")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}'
```

stuck Pod 의 PDB 확인 + 임시 완화.

> **🧠 PDB 임시 완화 패턴**
> 운영에선 PDB 영구 변경보다 **유지보수 시간대만 완화**:
> ```bash
> # 백업 후 일시 완화
> kubectl get pdb <name> -n <ns> -o yaml > /tmp/pdb-backup.yaml
> kubectl patch pdb <name> -n <ns> --type=merge -p '{"spec":{"maxUnavailable":1}}'
> # 업그레이드 후 원복
> kubectl apply -f /tmp/pdb-backup.yaml
> ```
> 또는 replicas 일시 증가로 disruptionsAllowed 확보 — 비용 잠시 늘리고 안전하게.

## 5. 업그레이드 후 통합 검증

```bash
# 모든 노드 새 버전
kubectl get nodes -o wide

# 모든 Pod Running
kubectl get pods -A | grep -vE 'Running|Completed'

# 핵심 워크로드 동작 (시나리오 앱)
kubectl get pods -n order
kubectl get ingress -n order
```

## 6. (옵션) 워크로드 부하 테스트로 회귀 검증

```bash
# Module 14 의 burst 시나리오를 다시 한 번
ALB_DNS=$(kubectl get ingress -n order msa -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -sX POST http://$ALB_DNS/api/orders -H 'Content-Type: application/json' -d '{"user_id":"u1","amount":100}' | jq
```

## 7. 다음 분기 업그레이드 준비

업그레이드 했으니 다음 분기 (1.31 → 1.32) 도 동일 흐름. 자동화 권장:
- Terraform 으로 cluster_version 변수만 변경
- CI 에서 plan → 사람 승인 → apply
- Insights 자동 점검을 PR check 로

> **🧠 Blue/Green 클러스터 전환의 PVC 처리**
> 새 클러스터(Green) 가 옛 클러스터(Blue) 의 EBS PVC 를 그대로 쓸 수 없음 — PV 의 nodeAffinity 가 옛 노드/AZ 에 묶임.
> 패턴 3가지:
> 1. **EBS Snapshot** → Green 에서 새 EBS 복원 → 새 PV 생성 (가장 안전, 다운타임 짧음).
> 2. **VolumeSnapshotContent CSI** 로 K8s 네이티브 스냅샷 → Green 에서 PVC 로 클론.
> 3. **App-level**: DB replication 으로 Green 에 복제 후 cutover (RPO 0 가능, 가장 복잡).
> Stateless workload 면 그냥 GitOps 로 재배포하면 끝 — Stateful 만 진짜 고민거리.

## 학습 확인

- addon 자동 업그레이드 옵션이 있는가? (`auto_update`)
- Karpenter 의 Drift 가 노드 그룹 업그레이드보다 좋은 점은?
- Blue/Green 클러스터 전환 시 데이터 (PVC) 는 어떻게?

다음: [quiz.md](./quiz.md)
