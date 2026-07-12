# Lab 01 — VM이 Pod 안에서 도는 구조를 봅니다

KubeVirt를 kind에 설치하고(중첩 가상화 제약으로 emulation 모드), VM이 어떻게 Pod로 스케줄되는지 확인합니다.

전제: kind, kubectl, virtctl(`curl -L ... /virtctl` 또는 krew). kind는 KVM이 없어 software emulation을 켭니다(느리지만 구조 확인 가능).

## Step 1. 클러스터와 KubeVirt 설치

```bash
kind create cluster --name kubevirt -q

# KubeVirt operator + CR
export VERSION=$(curl -s https://storage.googleapis.com/kubevirt-prow/release/kubevirt/kubevirt/stable.txt)
kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-operator.yaml"
kubectl apply -f "https://github.com/kubevirt/kubevirt/releases/download/${VERSION}/kubevirt-cr.yaml"

# kind는 KVM 없음 → software emulation 활성화
kubectl -n kubevirt patch kubevirt kubevirt --type merge \
  -p '{"spec":{"configuration":{"developerConfiguration":{"useEmulation":true}}}}'

kubectl -n kubevirt wait kubevirt kubevirt --for condition=Available --timeout=300s 2>/dev/null || \
  kubectl -n kubevirt get kubevirt kubevirt -o jsonpath='{.status.phase}'
```

## Step 2. 컴포넌트 지도

```bash
kubectl -n kubevirt get pods
echo ""
echo "=== 컴포넌트 역할 (theory §1) ==="
cat <<'EOF'
  virt-controller  VirtualMachine/VMI watch → virt-launcher Pod 생성
  virt-api         CRD 검증·서브리소스(console/vnc)
  virt-handler     노드 DaemonSet — VMI 상태 관리 (kubelet의 VM판)
EOF
kubectl get crd | grep kubevirt | head -6
```

## Step 3. VM 정의 — Deployment처럼 선언

```bash
kubectl apply -f - <<'EOF'
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata: { name: testvm }
spec:
  running: true
  template:
    metadata: { labels: { kubevirt.io/vm: testvm } }
    spec:
      domain:
        cpu: { cores: 1 }
        resources: { requests: { memory: 512Mi } }
        devices:
          disks:
            - { name: containerdisk, disk: { bus: virtio } }
          interfaces:
            - { name: default, masquerade: {} }
      networks:
        - { name: default, pod: {} }
      volumes:
        - name: containerdisk
          containerDisk:
            image: quay.io/kubevirt/cirros-container-disk-demo   # 작은 테스트 이미지
EOF
sleep 30
kubectl get vm testvm
kubectl get vmi testvm 2>/dev/null
```

## Step 4. ★ VM이 Pod 안에서 돕니다 — 구조 확인

```bash
echo "=== VMI를 실행하는 virt-launcher Pod ==="
kubectl get pods -l kubevirt.io=virt-launcher -o wide

echo ""
echo "=== 그 Pod 안의 컨테이너 (QEMU를 감쌉니다) ==="
LAUNCHER=$(kubectl get pod -l kubevirt.io=virt-launcher -o name | head -1)
kubectl get $LAUNCHER -o jsonpath='{.spec.containers[*].name}'; echo

echo ""
echo "=== Pod 안에서 QEMU 프로세스 확인 ==="
kubectl exec $LAUNCHER -c compute -- sh -c 'ps aux | grep -E "qemu|libvirt" | grep -v grep | head -3' 2>/dev/null || \
  echo "(compute 컨테이너 안에 libvirtd + qemu 프로세스 = 실제 VM)"
```

예상: virt-launcher Pod, 그 안에 `compute` 컨테이너, 그 안에 QEMU 프로세스. ✅ **VM = Pod 안의 QEMU**(theory §2) — K8s는 이것을 일반 Pod로 스케줄하고, 그 안에서 완전한 게스트 OS가 돕니다.

## Step 5. K8s가 VM을 Pod로 취급한다는 증거

```bash
echo "=== VM Pod도 일반 Pod처럼 스케줄·네트워크·리소스 ==="
kubectl get $LAUNCHER -o jsonpath='{.spec.nodeName}'; echo " ← 스케줄러가 노드 배정"
kubectl get $LAUNCHER -o jsonpath='{.status.podIP}'; echo " ← CNI가 IP 할당 (04)"
kubectl get $LAUNCHER -o jsonpath='{.spec.containers[0].resources}'; echo " ← 리소스 요청"

cat <<'EOF'

→ VM인데 K8s의 모든 것이 적용됩니다:
  스케줄러(노드 배정), CNI(네트워크 — 04), 리소스 관리, 모니터링
  이것이 "컨테이너 네이티브가 아닌 것을 K8s에 끼워 넣는" 방법 (guide)
EOF
```

## Step 6. VM 콘솔 접속 — 진짜 VM임을 확인

```bash
cat <<'EOF'
VM 콘솔 접속 (virtctl):
  virtctl console testvm      → VM의 시리얼 콘솔 (로그인 프롬프트)
  virtctl vnc testvm          → VNC (그래픽)
  virtctl start/stop/restart testvm  → VM 수명주기

→ 컨테이너의 kubectl exec와 다릅니다:
  컨테이너: 프로세스에 붙습니다
  VM: 게스트 OS의 콘솔에 붙습니다 (부팅·로그인·커널)
  = 진짜 VM (자체 커널, 완전 격리 — 03의 오른쪽 끝)
EOF
virtctl console testvm --timeout=1 2>/dev/null || echo "(virtctl console testvm 으로 접속 — CirrOS 로그인 프롬프트)"
```

## Step 7. 산출물

```markdown
# KubeVirt 구조 카드
- VM = virt-launcher Pod 안의 QEMU 프로세스 (K8s는 Pod로 스케줄)
- 컴포넌트: virt-controller/api(컨트롤) + virt-handler(노드) + virt-launcher(VM)
- CRD: VirtualMachine(running on/off) / VMI(실행 중) / DataVolume(디스크)
- K8s가 VM에 적용: 스케줄러·CNI(04)·리소스·모니터링
- 접속: virtctl console/vnc (게스트 OS 콘솔 — kubectl exec와 다름)
- 필요: 노드 KVM (kind는 emulation — 느림, 구조 확인용)
```

## 정리

lab-02에서 수명주기와 K8s 모델과의 긴장을 다룹니다. 유지.
