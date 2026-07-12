# 자가 점검 퀴즈

**Q1.** "VM이 Pod 안에서 돈다"는 구조를 설명하세요. K8s 관점과 VM 관점에서 각각 무엇인가요?

**Q2.** KubeVirt의 컴포넌트 셋과 각 역할은? 각각 K8s의 무엇에 대응하나요?

**Q3.** VirtualMachine과 VirtualMachineInstance의 차이는? Deployment/Pod와 어떻게 다른가?

**Q4.** K8s 전제와 VM 성질의 충돌을 네 가지 대비로 설명하세요.

**Q5.** 노드 드레인이 컨테이너와 VM에게 각각 무엇을 의미하나요? VM의 경우 무엇이 필요한가?

**Q6.** containerDisk와 PVC/DataVolume의 차이는? VM 스토리지에 05·09의 무엇이 적용되나요?

**Q7.** KubeVirt를 써야 하는 경우와 쓰지 말아야 하는 경우는? "다리"란 무슨 뜻인가요?

**Q8.** "복잡도 2배"의 의미와, 08의 추상 누수가 KubeVirt에서 극심한 이유는?

---

## 정답

**A1.** virt-controller가 VMI를 위해 virt-launcher Pod를 만들고, 그 Pod 안에서 libvirtd가 QEMU/KVM 프로세스(=실제 VM)를 실행합니다. K8s 관점: 그냥 일반 Pod이므로 스케줄러가 노드를 배정하고 CNI가 IP를 할당하고 리소스 관리·모니터링이 적용됩니다. VM 관점: 완전한 게스트 OS(자체 커널, 완전 격리 — 03의 오른쪽 끝)입니다. 즉 "컨테이너 네이티브가 아닌 것(VM)을 컨테이너로 감싸 K8s에 끼워 넣는" 방법입니다.

**A2.** virt-controller(VirtualMachine/VMI CRD를 watch해 virt-launcher Pod 생성 — 컨트롤러), virt-api(CRD 검증·서브리소스 console/vnc 제공 — API 확장), virt-handler(각 노드 DaemonSet으로 VMI 상태를 관리하고 libvirt/QEMU에 지시 — kubelet의 VM판). 즉 virt-controller는 컨트롤러 매니저, virt-api는 API 서버 확장, virt-handler는 kubelet에 각각 대응합니다.

**A3.** VirtualMachine은 VM의 정의와 원하는 상태(running: true/false)를 담는 상위 리소스로 Deployment에 비유되나 replicas가 아니라 on/off이며 재생성이 비쌉니다. VirtualMachineInstance(VMI)는 실행 중인 VM 하나로 Pod에 대응합니다. 차이: Deployment/Pod는 무상태 전제라 재생성이 저렴하지만, VirtualMachine을 껐다 켜면 스토리지에 따라 상태가 초기화(containerDisk)되거나 보존(PVC)되며, VMI는 라이브 마이그레이션 없이는 노드 이동이 상태 손실을 뜻합니다.

**A4.** ① 무상태 vs 상태 있음(VM은 디스크·메모리 상태). ② 재생성 저렴 vs 재생성 비쌈(VM은 부팅·상태 재구성 시간). ③ 수명 짧음 vs 수명 김(VM은 몇 달씩). ④ Pod 이동 자유 vs 이동=라이브 마이그레이션(복잡). (+수평 확장 vs 수직 확장이 흔함.) KubeVirt는 PVC·라이브 마이그레이션·스냅샷으로 이 긴장을 완화하지만 없애지 못합니다 — VM은 근본적으로 스테이트풀합니다.

**A5.** 컨테이너: 드레인 시 Pod를 evict하고 다른 노드에 새 Pod를 생성하면 끝(상태 없으니 저렴). VM: 죽이면 메모리·상태 손실이므로 라이브 마이그레이션(실행 중 VM의 메모리를 다른 노드로 반복 복사한 뒤 짧게 멈추고 전환)이 필요합니다. 요구: 공유 스토리지(RWX PVC) 또는 스토리지 마이그레이션, 노드 간 네트워크 대역, 마이그레이션 정책(VMIMigration), 그리고 PodDisruptionBudget. k8s 35의 노드 업그레이드가 VM에게는 마이그레이션 오케스트레이션이 됩니다.

**A6.** containerDisk: 컨테이너 이미지에 담긴 디스크로 재시작 시 초기화되는 무상태(골든 이미지·테스트용). PVC/DataVolume: 영속 디스크로 VM을 꺼도 유지되는 상태 보존(실제 워크로드). VM 스토리지에는 05의 3형태 매칭이 적용되어 블록 RWO가 자연스럽고(단일 마운트), 라이브 마이그레이션엔 RWX가 필요합니다. 09의 스테이트풀 판단 프레임이 극대화되어 스토리지·백업·복구가 KubeVirt 운영의 핵심이 됩니다. DataVolume(CDI)은 기존 VM 디스크·ISO·클라우드 이미지를 PVC로 import하고 clone으로 복제합니다.

**A7.** 써야 하는 경우: 컨테이너화할 수 없는 워크로드(레거시, 특수 OS/커널, 커널 모듈, 하드웨어 의존, 규제상 완전 격리) + 컨테이너와 VM을 하나의 K8s API로 통합 관리 원함 + 양쪽 운영 역량. 쓰지 말아야 할 경우: 컨테이너화 가능한데 편의로(재작성이 대개 이득), 대규모 VM 팜(전용 하이퍼바이저가 성숙), K8s·가상화 양쪽 역량 부족. "다리"란: 레거시를 KubeVirt로 K8s에 올린 뒤 점진적으로 컨테이너화해 결국 VM을 제거하는 마이그레이션 경로 — KubeVirt가 목적지가 아니라 이행 수단인 경우가 많습니다.

**A8.** KubeVirt 운영은 K8s와 가상화(libvirt/QEMU/KVM) 양쪽 지식을 요구합니다 — VM 문제가 K8s 층(스케줄·스토리지·네트워크)인지 가상화 층(QEMU·게스트 OS·커널)인지 구분하고 두 세계의 도구·개념·장애 모드를 모두 다뤄야 하므로 운영 복잡도가 2배가 됩니다. 08의 추상 누수가 극심한 이유: 다른 5단 추상(Knative 등)은 아래가 K8s 개념이지만, KubeVirt는 아래가 **컨테이너 네이티브가 아닌 것(게스트 OS·하이퍼바이저)**이라, 추상이 새면 K8s 지식으로는 부족하고 가상화 지식이 별도로 필요합니다(사고 사례: 부팅 실패의 원인이 게스트 OS fstab인데 아무도 virtctl console을 볼 줄 몰랐습니다).
