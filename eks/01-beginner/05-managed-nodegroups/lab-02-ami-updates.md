# Lab 02 — 업데이트 제어, 자동 복구, nodeadm 커스터마이즈

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. 업데이트 설정과 자동 복구 켜기

```bash
aws eks update-nodegroup-config --cluster-name $CLUSTER --nodegroup-name spot-batch \
  --region $AWS_REGION \
  --update-config maxUnavailable=1 \
  --node-repair-config enabled=true
aws eks describe-nodegroup --cluster-name $CLUSTER --nodegroup-name spot-batch --region $AWS_REGION \
  --query 'nodegroup.{update:updateConfig,repair:nodeRepairConfig}'
```

✅ `maxUnavailable=1` = 업데이트 때 한 번에 한 노드만 비웁니다(k8s 35의 안전 우선 설정). `nodeRepair` = NotReady 노드 자동 교체 — k8s 38 #10의 1차 대응 자동화.

## Step 2. AMI 업데이트 메커니즘 — 명령과 동작 (실행은 선택)

```bash
# 현재 AMI 릴리스와 최신 비교
aws eks describe-nodegroup --cluster-name $CLUSTER --nodegroup-name spot-batch --region $AWS_REGION \
  --query 'nodegroup.{ami:amiType,release:releaseVersion,version:version}'
# 같은 K8s 버전의 최신 AMI로 교체 (트리거하면 롤링 시작 — 10~20분, 노드 수에 비례)
# aws eks update-nodegroup-version --cluster-name $CLUSTER --nodegroup-name spot-batch --region $AWS_REGION
```

실행한다면 관찰 포인트(k8s 35 lab-02와 동일 메커니즘):
```bash
kubectl get nodes -w               # 새 노드 추가 → 구 노드 SchedulingDisabled → 소멸
kubectl get pdb -A                 # PDB가 드레인 속도를 조율
aws eks describe-update --name <update-id> ...    # 진행 상태 API
```

✅ **노드 OS 패치의 정체 = AMI 교체 롤링** — 패치를 "설치"하지 않고 노드를 "갈아치운다"(불변 인프라). 이 트리거를 분기 루틴(k8s 35 runbook)에 넣는 것이 표준 모드 운영이고, 이걸 자동으로 해주는 게 Auto Mode(04)였습니다.

## Step 3. Bottlerocket 풀 맛보기

```bash
cat > br-pool.yaml <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata: { name: $CLUSTER, region: $AWS_REGION }
managedNodeGroups:
- name: br-test
  amiFamily: Bottlerocket
  instanceType: t3.medium
  desiredCapacity: 1
  minSize: 0
  maxSize: 1
  labels: { pool: br }
  taints: [{ key: pool, value: br, effect: NoSchedule }]
EOF
eksctl create nodegroup -f br-pool.yaml
kubectl get nodes -o wide | grep -i bottle    # OS-IMAGE 열에서 Bottlerocket 확인
```

```bash
# 일반 OS처럼 다루려 해보기
BR_NODE=$(kubectl get nodes -l pool=br -o jsonpath='{.items[0].metadata.name}')
kubectl debug node/$BR_NODE -it --image=public.ecr.aws/docker/library/busybox:stable -- \
  chroot /host sh -c 'cat /etc/os-release; which yum dnf apt 2>&1' 2>&1 | tail -4
kubectl get pods -o name | grep node-debugger | xargs -r kubectl delete
```

✅ 패키지 매니저가 **없습니다** — "설치할 수 없는 OS"가 곧 보안 표면 최소화입니다. 설정은 부팅 시 TOML로만, 변경은 AMI 교체로만 — 불변 인프라의 극단이자 Auto Mode(04)의 기반.

## Step 4. nodeadm 커스터마이즈 (AL2023) — 개념 검증

시작 템플릿 userdata로 kubelet을 만지는 표준 통로(theory §2). 실제 적용 대신 구조 확인:

```yaml
# launch template userdata에 들어갈 NodeConfig (MIME 멀티파트로 포장됨)
apiVersion: node.eks.aws/v1alpha1
kind: NodeConfig
spec:
  kubelet:
    config:
      maxPods: 58                                   # eks 07(IP)와 연결되는 값!
      registerWithTaints: [{ key: boot, value: pending, effect: NoSchedule }]
    flags: ["--node-labels=custom=via-nodeadm"]
```

✅ 용도 예: maxPods 조정(prefix delegation과 세트 — 07), 부팅 직후 taint(준비 전 배치 차단), 커스텀 라벨. **건드릴수록 Auto Mode와 멀어진다**는 트레이드오프(04)를 기억 — "정말 필요한 커스터마이즈인가"가 먼저입니다.

## Step 5. 운영 달력에 넣을 것 (산출물)

```markdown
# 표준 모드 노드 운영 루틴
- 월간: AMI releaseVersion vs 최신 비교 → 분기 내 update-nodegroup-version
- 항시: nodegroup health.issues 모니터링 + nodeRepair on
- 업데이트 전: PDB 점검 (k8s 35 preflight) / maxUnavailable 재확인
- 연간: AMI 계열 재평가 (AL2023 ↔ Bottlerocket ↔ Auto Mode 이주)
```

## 정리

```bash
bash cleanup.sh    # br-test, spot-batch 노드그룹 삭제 (비용!)
```
