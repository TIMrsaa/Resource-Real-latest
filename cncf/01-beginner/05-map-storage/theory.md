# 이론 — CSI 해부, 역할 분류 지도, 3형태, 관리형 vs 자체 운영

> **🌱 17세 눈높이 비유: 학교의 사물함 체계**
> - **블록 스토리지** = 개인 사물함 — 한 명이 통째로 씁니다(DB의 디스크). 빠르지만 공유 불가
> - **파일 스토리지** = 공용 자료실 — 여럿이 같은 폴더를 봅니다(공유 볼륨)
> - **오브젝트 스토리지** = 택배 보관소 — 번호표(키)로 넣고 꺼냅니다. 무한히 크지만 파일시스템이 아닙니다(S3류)
> - **CSI** = 사물함 설치 표준 규격 — 학교(K8s)는 규격만 알면 어느 업체(EBS·Ceph·Longhorn) 사물함이든 설치 가능
> - **CSI 사이드카** = 규격 담당 행정팀 — "사물함 신청서(PVC) 접수 → 업체에 발주(provisioner) → 교실에 배정(attacher)"을 업체 대신 처리해줘서, 업체는 자기 사물함 만드는 법만 알면 됩니다
> - **Rook** = 사물함 업체가 아니라 **관리 용역** — 대형 업체(Ceph)의 사물함 수천 개를 대신 설치·수리·교체
> - **데이터 중력** = 사물함에 짐이 차면 학교를 못 옮깁니다 — 그래서 첫 계약이 제일 중요

---

## 1. CSI — 세 번째 인터페이스 (CRI·CNI에 이어)

```
        PVC 생성                          Pod 스케줄
           │                                  │
┌──────────▼──────────────┐        ┌──────────▼─────────────┐
│ 컨트롤러 플레인 (Deployment) │        │ 노드 (DaemonSet)        │
│  external-provisioner ──┼─CSI──▶ │  node-driver-registrar │
│  external-attacher      │ gRPC   │  kubelet ──▶ NodeStage/ │
│  external-snapshotter   │        │           NodePublish   │
│  + 드라이버 컨테이너      │        │  + 드라이버 컨테이너      │
└─────────────────────────┘        └────────────────────────┘
```

- **사이드카 패턴의 발명**: K8s 감시(watch PVC/VolumeAttachment)는 공용 사이드카들이 하고, 벤더 드라이버는 **CSI gRPC 함수만**(CreateVolume, ControllerPublish, NodeStage...) 구현합니다 — 벤더가 K8s 내부를 몰라도 되는 경계선
- 프로비저닝의 여정(lab-02에서 실측): PVC → provisioner가 CreateVolume → PV 생성·바인딩 → Pod 스케줄 → attacher가 노드에 연결 → kubelet이 NodeStage(포맷·글로벌 마운트)→NodePublish(Pod 경로 마운트)
- 진단이 층으로 나뉩니다: Pending(프로비저닝 층) / Attach 실패(연결 층) / Mount 실패(노드 층) — 각각 보는 로그가 다릅니다
- CSI 스냅샷 표준: VolumeSnapshot CRD — Velero(k8s 36)가 이것을 타고 백업합니다

## 2. 전수 지도 — 역할로 가릅니다 (기준 시점 2026-06, 성숙도는 lab-01 재확인)

### 오케스트레이터 (스토리지를 저장하지 않습니다!)

| 프로젝트 | 성숙도 | 한 줄 |
|---|---|---|
| **Rook** | Graduated | **Ceph의 K8s 오퍼레이터** — 설치·복구·업그레이드 자동화. 평가 대상은 Ceph+Rook 세트 |

### K8s 네이티브 스토리지 시스템

| 프로젝트 | 성숙도 | 한 줄 |
|---|---|---|
| **Longhorn** | Incubating | 분산 블록 — 각 볼륨을 레플리카로 노드들에 복제. 단순 지향(Rancher 계열) |
| **OpenEBS** | Sandbox급* | "컨테이너에 담긴 스토리지"(CAS) — 로컬 PV부터 복제 엔진까지 스펙트럼 |
| TopoLVM / local-path 계열 | Sandbox~ | 로컬 디스크의 동적 프로비저닝 — 성능 최우선·복제는 앱이(DB 자체 복제) |

### 대형 스토리지 시스템 (K8s 밖에서 온 거인들)

| 프로젝트 | 소속 | 한 줄 |
|---|---|---|
| Ceph | (자체/LF 계열) | 블록+파일+오브젝트 통합 분산 스토리지 — Rook의 피대상. 강력하되 운영 무게급 |
| **CubeFS** | Graduated | 분산 파일+오브젝트 — 대규모(중국 빅테크 출신) 파일 워크로드 |
| MinIO | (자사 — AGPL) | S3 호환 오브젝트 — 비CNCF, 라이선스(AGPL) 검토 필수 (01의 축) |
| JuiceFS 등 | 외부 | 오브젝트 위에 파일시스템을 얹는 계열 |

### 백업·이동 (스토리지의 반쪽)

| 프로젝트 | 성숙도 | 한 줄 |
|---|---|---|
| **Velero** | (VMware 계열 오픈소스) | 클러스터 리소스+볼륨 백업/복원 — k8s 36의 주인공. CSI 스냅샷 연동 |
| Piraeus/LINSTOR 등 | Sandbox~ | DRBD 계열 복제 — 특수 요구 지대 |

### 클라우드 CSI 드라이버 (지도의 실무 기본값)

```
EBS/EFS CSI(eks), GCP PD, Azure Disk... — "시스템은 클라우드가 운영, 우리는 드라이버만"
→ 대부분 조직의 올바른 출발점 (자체 운영은 §4의 조건이 갖춰졌을 때)
```

## 3. 3형태 × 워크로드 매칭

| 형태 | 접근 모델 | K8s에서 | 맞는 워크로드 |
|---|---|---|---|
| 블록 | 단일 노드 마운트(RWO) | EBS CSI, Longhorn, Ceph RBD | DB, 단일 쓰기 상태 |
| 파일 | 다중 노드 공유(RWX) | EFS CSI, CephFS, CubeFS | 공유 콘텐츠, 레거시 앱, ML 데이터셋 |
| 오브젝트 | API(S3) — 마운트 아님 | S3, MinIO, Ceph RGW | 아카이브, 백업, 정적 자산, 데이터레이크 |

고전 실수 두 가지: RWX가 필요한데 블록을 고름(Multi-Attach 에러 — eks의 EBS로 RWX 시도), 오브젝트에 파일시스템 의미론 기대(목록·rename이 비쌉니다).

## 4. 관리형 vs 자체 운영 — 판단 축

```
관리형(EBS/EFS/S3)이 기본값인 이유: 내구성·운영·업그레이드가 남의 새벽
자체 운영(Rook-Ceph/Longhorn/CubeFS)이 정당해지는 조건:
  - 베어메탈/온프레미스 (관리형이 없습니다 — 가장 흔한 이유)
  - 비용 곡선의 역전 (초대규모에서 관리형 프리미엄 > 운영 인건비)
  - 데이터 주권·규제 (특정 위치·통제 요구)
  - 특수 성능 요구 (로컬 NVMe 직결 등)
전제 조건: "이것을 새벽 3시에 고칠 사람"이 조직에 실재할 것 — 스토리지 운영은
분산 시스템 운영입니다 (Ceph의 무게는 유명합니다 — Rook이 덜어주지만 없애주지 않습니다)
```

**데이터 중력**: 데이터가 쌓일수록 그 위 서비스들이 끌려와 앉고, 이사 비용(전송 시간·비용·정합성 검증·이중 운영 기간)이 커집니다 — 스토리지 결정이 이 지도에서 가장 신중해야 하는 이유이자, 01의 소견서(지속성)가 가장 무겁게 적용되는 곳.

## 5. 소스/도구에서 확인하기

- CSI 명세: https://github.com/container-storage-interface/spec
- 사이드카들: https://kubernetes-csi.github.io/docs/ (provisioner/attacher/snapshotter/registrar)
- Rook: https://rook.io / Longhorn: https://longhorn.io / CubeFS: https://cubefs.io
- Velero: https://velero.io (k8s 36 복습)
- 성숙도 재확인: lab-01 (landscape.yml)

## 요약 카드

| 질문 | 답 |
|------|----|
| CSI의 구조? | 공용 사이드카(K8s 감시) + 벤더 드라이버(gRPC 함수만) — 벤더가 K8s를 몰라도 되는 경계 |
| 진단의 층? | Pending(프로비저닝)/Attach/Mount — 층마다 로그가 다릅니다 |
| Rook의 정체? | 스토리지가 아니라 Ceph의 오퍼레이터 — 시스템 vs 오케스트레이터 구분이 지도의 뼈대 |
| 3형태 매칭? | 블록=RWO·DB / 파일=RWX·공유 / 오브젝트=API·아카이브 — RWX에 블록 금지 |
| 자체 운영의 조건? | 온프레/초대규모/주권/특수 성능 + "새벽에 고칠 사람"의 실재 |
| 이 지도의 제1규율? | 데이터 중력 — 무를 수 없는 결정, 소견서(01)를 가장 무겁게 |
