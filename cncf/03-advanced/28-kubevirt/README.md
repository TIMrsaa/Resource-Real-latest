# 28 — KubeVirt 심층: 가상머신을 Pod처럼

> 08의 사다리에서 5단(상위 추상)의 특이한 주민. "무엇 위의 추상인가"를 물었을 때 KubeVirt의 답은 **VM 위**입니다 — 컨테이너로 못 옮기는 워크로드(레거시 앱, 특수 OS, 커널 모듈 의존)를 K8s 안에서 VM으로 돌립니다. 이 모듈은 그 마법의 구조(VM이 어떻게 Pod 안에서 도는가 — virt-launcher가 QEMU를 감쌉니다), 그리고 근본적 긴장(K8s는 무상태·재생성을 전제하는데 VM은 상태·수명이 깁니다)을 팝니다. 컨테이너 네이티브가 아닌 것을 컨테이너 플랫폼에 얹는 것의 대가를 정직하게 다룹니다.

## 학습 목표

1. KubeVirt의 아키텍처(virt-controller/handler/launcher + QEMU/KVM)를 이해합니다
2. VM이 어떻게 Pod 안에서 실행되는가 — virt-launcher가 QEMU를 감싸는 구조를 압니다
3. VirtualMachine/VirtualMachineInstance CRD와 컨테이너 워크로드의 차이를 압니다
4. VM의 상태·스토리지·라이브 마이그레이션이 K8s 모델과 부딪히는 지점을 압니다
5. "언제 KubeVirt인가"(컨테이너화 못 하는 것) 판단과 그 대가를 압니다

## 선행: 08(추상 사다리 5단), 03(런타임·격리), 05(스토리지), 09(스테이트풀) · 도구: kind, kubectl (개념+데모)
## 비용: 없음 (kind — 중첩 가상화 제약으로 개념 중심)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-vm-in-pod.md](./lab-01-vm-in-pod.md) — 아키텍처, VM이 Pod 안에서 도는 구조
3. [lab-02-vm-lifecycle-and-tension.md](./lab-02-vm-lifecycle-and-tension.md) — VM 수명주기, K8s 모델과의 긴장
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
