# 이론 — 아키텍처, VM in Pod, CRD, 상태·마이그레이션, 판단

> **🌱 17세 눈높이 비유: 컨테이너 화물선에 자동차를 싣기**
> - **컨테이너 화물선(K8s)** = 표준 컨테이너를 싣도록 설계됐습니다 — 규격이 맞아야 효율적
> - **자동차(VM)** = 컨테이너 규격이 아닙니다 (레거시 앱, 특수 OS)
> - **KubeVirt의 트릭** = 자동차를 **컨테이너 안에 넣어서** 싣습니다 (virt-launcher가 QEMU를 감쌉니다)
>   → 화물선(K8s)은 그것을 표준 컨테이너로 취급 → 크레인(스케줄러)·항로(네트워크)를 적용
> - **긴장** = 자동차는 시동이 걸려 있고(상태) 무겁습니다(수명·이동 비용) — 컨테이너처럼 막 버리고 새로 못 만듭니다
> - **라이브 마이그레이션** = 달리는 자동차를 멈추지 않고 다른 배로 옮기기 (메모리째로) — 복잡하지만 가능
> - **판단** = "컨테이너로 만들 수 있으면 만들어라. 정말 못 하는 것만 자동차로 싣는다"

---

## 1. 아키텍처

```
컨트롤 플레인:
  virt-controller   VirtualMachine/VMI CRD를 watch → virt-launcher Pod 생성
  virt-api          API 확장 (CRD 검증·서브리소스: console, vnc...)

노드(DaemonSet):
  virt-handler      각 노드에서 VMI 상태 관리 (kubelet의 VM판)
                    → libvirt/QEMU에 지시

VM 실행:
  virt-launcher (Pod) ── 컨테이너 안에서 ──▶ libvirtd → QEMU/KVM → VM
    │
    └ 이 Pod가 곧 "VM을 담은 컨테이너"
      K8s는 이것을 일반 Pod로 스케줄·네트워크·모니터
```

## 2. VM in Pod — 마법의 구조

```
VirtualMachineInstance(VMI) 생성
   │ virt-controller
   ▼
virt-launcher Pod (일반 Pod처럼 스케줄됨)
   │  안에서:
   ├ libvirtd (VM 관리)
   ├ QEMU 프로세스 = 실제 VM (KVM 하드웨어 가속)
   └ virt-launcher가 QEMU 수명주기를 K8s와 연결

핵심:
  VM = virt-launcher Pod 안의 QEMU 프로세스
  → K8s 관점: 그냥 Pod (스케줄·네트워크·리소스 적용)
  → VM 관점: 완전한 게스트 OS (자체 커널, 완전 격리)

필요 조건:
  노드에 KVM (하드웨어 가상화) — /dev/kvm
  중첩 가상화(클라우드 VM 위 K8s면) 또는 베어메탈
  → kind(컨테이너 노드)에서는 KVM 없어 emulation(느림) 또는 개념만
```

## 3. CRD — VM을 선언합니다

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata: { name: legacy-app }
spec:
  running: true                          # VM을 켤지 (Deployment의 replicas 같은)
  template:
    spec:
      domain:
        cpu: { cores: 2 }
        memory: { guest: 4Gi }
        devices:
          disks:
            - { name: rootdisk, disk: { bus: virtio } }
          interfaces:
            - { name: default, masquerade: {} }   # Pod 네트워크에 연결
      networks:
        - { name: default, pod: {} }
      volumes:
        - name: rootdisk
          containerDisk: { image: quay.io/.../fedora-cloud }   # 또는 PVC(영속)
```

| KubeVirt | 컨테이너 대응 | 차이 |
|---|---|---|
| VirtualMachine | Deployment | running으로 on/off, 재생성 비쌈 |
| VirtualMachineInstance(VMI) | Pod | 실행 중인 VM 하나 |
| DataVolume | PVC + import | VM 디스크 준비(이미지 import·clone) |
| VirtualMachineSnapshot | (없음) | VM 상태 스냅샷 |

## 4. 상태와 스토리지 — 긴장의 중심

```
VM 디스크 = 상태 (컨테이너의 무상태와 정반대)

스토리지 옵션:
  containerDisk: 이미지에 담긴 디스크 (무상태 — 재시작 시 초기화, 골든 이미지)
  PVC/DataVolume: 영속 디스크 (05의 스토리지 — 블록 RWO가 자연스러움)
    → VM은 블록 스토리지(단일 마운트)와 잘 맞습니다 (05의 3형태)
    → 라이브 마이그레이션하려면 RWX 또는 특수 처리 필요

DataVolume (CDI - Containerized Data Importer):
  이미지·ISO·기존 VM 디스크를 PVC로 import → VM이 부팅
  clone: 골든 이미지에서 VM 복제

★ 09의 스테이트풀 판단 프레임이 극대화:
  VM은 가장 스테이트풀 → 스토리지·백업·복구가 핵심 (05·k8s 36)
```

## 5. 라이브 마이그레이션 — VM 이동의 복잡성

```
컨테이너: Pod를 죽이고 다른 노드에 새로 생성 (상태 없으니 저렴)
VM:       죽이면 상태·메모리 손실 → 라이브 마이그레이션 필요

라이브 마이그레이션:
  실행 중 VM의 메모리를 다른 노드로 복사 (반복적으로 dirty page 전송)
  → 마지막에 짧게 멈추고 전환 (downtime 최소)
  요구: 공유 스토리지(RWX PVC) 또는 스토리지 마이그레이션, 노드 간 네트워크 대역

언제 필요?
  노드 유지보수(드레인 — k8s 35), 노드 장애 대비, 부하 재분산
  → 컨테이너의 "그냥 재스케줄"이 VM에서는 이 복잡한 절차

★ 노드 드레인(k8s 35)이 VM에게는 라이브 마이그레이션 트리거
  PodDisruptionBudget + 마이그레이션 정책 필요 (09의 StatefulSet 교훈 확대)
```

## 6. 네트워킹 — Pod 네트워크에 VM을

```
masquerade: VM을 Pod 네트워크 뒤에 NAT (기본, 간단)
bridge: VM을 Pod 네트워크에 직접
Multus + 보조 네트워크: VM에 여러 NIC (전통 VM처럼)
  → 04의 CNI가 VM에도 적용, 복잡한 네트워크는 Multus로

★ VM은 전통적으로 여러 NIC·VLAN을 기대 → Multus(멀티 네트워크)와 자주 결합
```

## 7. 판단 — 언제 KubeVirt인가

```
KubeVirt가 맞는 경우:
  - 컨테이너화할 수 없는 워크로드 (레거시, 특수 OS/커널, 하드웨어 의존)
  - 컨테이너와 VM을 하나의 K8s API로 통합 관리 원함
  - 기존 VM 인프라(vSphere)를 K8s로 통합·이전
  - 완전 격리가 규제상 필요 (03의 오른쪽 끝)

KubeVirt가 아닌 경우:
  - 컨테이너화할 수 있는데 "VM이 편해서" (재작성 비용 < 장기 VM 운영 비용)
  - 대규모 VM 팜 (전용 하이퍼바이저가 더 성숙할 수 있음)
  - K8s·가상화 양쪽 운영 역량이 없음 (복잡도 2배)

★ 원칙: "컨테이너로 만들 수 있으면 만들어라. 정말 못 하는 것만 KubeVirt"
  KubeVirt는 마이그레이션 다리이지 목적지가 아닌 경우가 많습니다
  (레거시를 KubeVirt로 옮긴 뒤 점진적 컨테이너화)
```

## 8. 소스/도구에서 확인하기

- KubeVirt: https://kubevirt.io/user-guide/ — architecture, VM lifecycle, migration
- CDI: https://github.com/kubevirt/containerized-data-importer
- virtctl: VM 콘솔·VNC·수명주기 CLI
- 08(추상 사다리)·09(스테이트풀)·05(스토리지)·k8s 35(드레인) 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| VM in Pod? | virt-launcher Pod 안에서 QEMU 실행 → K8s가 Pod로 스케줄 |
| 컴포넌트? | virt-controller·virt-api(컨트롤) + virt-handler(노드) + virt-launcher(VM) |
| 필요 조건? | 노드 KVM(하드웨어 가상화) — kind에서는 개념/emulation |
| CRD? | VirtualMachine(on/off) / VMI(실행 중) / DataVolume(디스크) |
| 근본 긴장? | K8s(무상태·재생성 저렴) vs VM(상태·수명 길고 이동 비쌈) |
| 노드 드레인? | VM에게는 라이브 마이그레이션 트리거 (k8s 35 확대) |
| 스토리지? | 블록 RWO 자연, 라이브 마이그레이션엔 RWX 필요 (05·09) |
| 언제? | 컨테이너화 못 하는 것 + 통합 관리 — "못 하는 것만, 다리로" |
