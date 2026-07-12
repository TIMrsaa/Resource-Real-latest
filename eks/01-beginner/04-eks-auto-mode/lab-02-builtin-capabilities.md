# Lab 02 — 내장 기능 체험과 제약의 실측

## Step 1. 내장 스토리지 — EBS CSI를 설치한 적 없는데

```bash
kubectl get storageclass
# Auto Mode 활성 시 ebs 계열 기본 클래스 존재 여부 확인
cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: { name: auto-ebs }
provisioner: ebs.csi.eks.amazonaws.com        # ★ Auto Mode 내장 프로비저너
volumeBindingMode: WaitForFirstConsumer
parameters: { type: gp3 }
EOF
```

```bash
# PVC + Pod로 검증 (k8s 08의 실험을 내장 드라이버로)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: auto-data }
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: auto-ebs
  resources: { requests: { storage: 1Gi } }
---
apiVersion: v1
kind: Pod
metadata: { name: auto-writer }
spec:
  nodeSelector: { eks.amazonaws.com/compute-type: auto }
  volumes: [{ name: d, persistentVolumeClaim: { claimName: auto-data } }]
  containers:
  - name: c
    image: public.ecr.aws/docker/library/busybox:stable
    command: [sh, -c, 'echo automode-data > /data/f && sleep 3600']
    volumeMounts: [{ name: d, mountPath: /data }]
    resources: { requests: { cpu: 250m, memory: 256Mi } }
EOF
kubectl wait --for=condition=Ready pod/auto-writer --timeout=300s
kubectl exec auto-writer -- cat /data/f    # automode-data
```

✅ **aws-ebs-csi-driver를 설치(eks 10)하지 않았는데** 볼륨이 붙었습니다 — 내장 컨트롤러(`ebs.csi.eks.amazonaws.com`)의 일. 단, 프로비저너 이름이 표준(`ebs.csi.aws.com`)과 다름을 기억 — 기존 StorageClass를 그대로 못 쓰는 마이그레이션 포인트입니다.

## Step 2. 노드 접근 불가 — 제약의 실측

```bash
NODE=$(kubectl get pod auto-writer -o jsonpath='{.spec.nodeName}')
# k8s 26에서 쓰던 노드 진입 시도
kubectl debug node/$NODE -it --image=public.ecr.aws/docker/library/busybox:stable -- chroot /host sh 2>&1 | tail -2
# SSM/SSH도 불가 (인스턴스에 SSM 에이전트 접근 차단)
```

예상: 거부되거나 chroot가 제한됩니다 (Bottlerocket + Auto Mode 잠금).

✅ **"노드 안"이라는 디버깅 층이 통째로 사라졌습니다** — k8s 26/27에서 노드에서 하던 진단(crictl, CNI 설정 확인)은 Auto Mode에선 불가능하고, 그 역할을 관측성(로그/메트릭 — eks 12)과 AWS 지원이 대신합니다. 트레이드오프를 몸으로 확인한 것.

## Step 3. 커스텀 NodePool — Karpenter 문법 예습 (17)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: karpenter.sh/v1
kind: NodePool
metadata: { name: small-only }
spec:
  template:
    spec:
      requirements:
      - { key: "eks.amazonaws.com/instance-category", operator: In, values: [t, m] }
      - { key: "eks.amazonaws.com/instance-cpu", operator: In, values: ["2", "4"] }
      - { key: "karpenter.sh/capacity-type", operator: In, values: [on-demand] }
      nodeClassRef: { group: eks.amazonaws.com, kind: NodeClass, name: default }
      taints:
      - { key: pool, value: small, effect: NoSchedule }
  limits: { cpu: "8" }                          # 이 풀의 총 CPU 상한 (폭주 방지!)
  disruption: { consolidationPolicy: WhenEmptyOrUnderutilized }
EOF
kubectl get nodepool small-only
```

```bash
# 이 풀로만 가는 Pod (taint 매칭 — k8s 12의 그 문법)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: small-pod
  labels: { run: small-pod }
spec:
  nodeSelector: { karpenter.sh/nodepool: small-only }
  tolerations:
    - key: pool
      value: small
      effect: NoSchedule
  containers:
    - name: small-pod
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
      resources:
        requests: { cpu: 500m, memory: 256Mi }
EOF
kubectl get nodes -L karpenter.sh/nodepool -w    # small-only 소속 노드 출현
```

✅ "요구사항을 선언하면 맞는 인스턴스가 온다" — Karpenter 설계 사고의 핵심을 내장판으로 체험했습니다. `limits`(풀 상한)는 **비용 폭주의 안전벨트** — 운영에서 필수입니다. 내부 알고리즘(어떤 인스턴스를 왜 고르는지)은 모듈 17에서 팝니다.

## Step 4. 강제 교체에 견디는가 — 운영 적합성 셀프 점검

theory §3의 "21일마다 모든 노드 교체"를 견딜 준비가 됐는지, k8s 파트 체크리스트로:

```markdown
- [ ] 모든 Deployment에 PDB가 있는가 (k8s 19)
- [ ] graceful shutdown (SIGTERM 처리 + preStop) (k8s 14)
- [ ] 상태는 PVC/외부 저장소에 (emptyDir에 소중한 것 없음) (k8s 08)
- [ ] 단일 replica 워크로드 없음 (교체 중 다운 허용이 아니라면)
→ 하나라도 No면: Auto Mode가 아니라 그 워크로드가 문제입니다 — 어차피 고쳐야 할 빚
```

## 정리

```bash
bash cleanup.sh
```
