# 이론 — 세 드라이버의 구조, 스냅샷/확장, 선택 기준

> **🌱 17세 눈높이 비유: 개인 사물함, 동아리방 공용 책장, 학교 창고**
> - **EBS** = 개인 사물함: 빠르고 내 것이지만 **한 명만** 열쇠를 갖고(RWO), 사물함은 그 건물(AZ)에 붙박이
> - **EFS** = 동아리방 공용 책장: 여럿이 동시에(RWX), 어느 건물에서든 접근, 쓰는 만큼 크기가 늘어남 — 대신 개인 사물함보다 손이 느립니다
> - **S3 Mountpoint** = 학교 창고를 책장처럼 쓰는 것: 엄청난 양을 싸게, 단 "책장인 척"일 뿐이라 책장처럼 막 다루면(잠금, 이어쓰기) 안 됩니다
> - **스냅샷** = 사물함 내용물의 사진 — 사진으로 새 사물함을 그대로 복원할 수 있습니다

---

## 1. CSI 복습 30초 (k8s 08의 그 구조)

```
controller 플러그인 (Deployment): 볼륨 생성/삭제/스냅샷/확장 — AWS API 호출 (권한: 09!)
node 플러그인 (DaemonSet): attach된 볼륨을 마운트/포맷 — 노드에서
```

EKS에선 셋 다 **관리형 애드온**(11)으로 설치 가능: `aws-ebs-csi-driver`, `aws-efs-csi-driver`, `aws-mountpoint-s3-csi-driver`. 권한은 Pod Identity/IRSA로(09에서 배운 그대로).

## 2. EBS CSI — 블록의 운영 동작

### StorageClass 파라미터 (gp3의 다이얼)

```yaml
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"            # gp3는 용량과 독립적으로 IOPS/처리량 조절!
  throughput: "125"
  encrypted: "true"        # 기본 켜기 — 비용 0의 보안
allowVolumeExpansion: true # ★ 확장 허용 (이 줄이 없으면 resize 불가)
volumeBindingMode: WaitForFirstConsumer   # AZ 함정 방지 (k8s 08)
```

### VolumeSnapshot — 3종 세트

```yaml
VolumeSnapshotClass (어떻게 찍나: ebs.csi.aws.com)
VolumeSnapshot      (이 PVC를 찍어라) → EBS 스냅샷 생성
새 PVC의 dataSource (이 스냅샷에서 복원하세요) → 새 볼륨
```

→ Velero(k8s 36)의 CSI 스냅샷 모드가 내부적으로 쓰는 것이 바로 이 체계. 용도: 마이그레이션 직전 보험, staging 데이터 복제, (정책적 백업은 Velero/DLM으로 — 24).

### 온라인 확장 — 운영의 효자

```
kubectl patch pvc data -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
→ controller가 EBS ModifyVolume → node가 파일시스템 확장 → Pod 무중단!
```

제약: 늘리기만 가능(축소 불가), EBS는 같은 볼륨 수정 후 6시간 쿨다운, StorageClass에 `allowVolumeExpansion` 필수.

## 3. EFS CSI — RWX의 세계

- NFS 기반 공유 파일시스템: **여러 노드의 여러 Pod이 동시 마운트(RWX)** — k8s 08에서 Multi-Attach로 좌절한 그 요구의 답
- AZ 무관(리전 서비스 + AZ별 mount target) — EBS의 AZ 함정 없음
- 동적 프로비저닝 = **access point** 단위: 하나의 EFS 파일시스템 안에 PVC마다 격리된 디렉터리+POSIX 신원

```yaml
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: fs-xxxx          # 파일시스템은 미리 (인프라 영역)
  directoryPerms: "700"
```

성격 주의: 지연이 EBS보다 크고(네트워크 파일시스템), 소량 랜덤 IO에 약합니다 — **DB를 EFS에 올리지 마세요**(단골 사고). 어울리는 것: 공유 콘텐츠(업로드 파일, 모델), 다중 Pod 읽기/쓰기, 레거시 NFS 요구.

## 4. Mountpoint for S3 CSI — 객체를 파일처럼

- S3 버킷을 마운트 — **대용량 순차 읽기**(ML 학습 데이터, 로그 분석)에 최적
- POSIX가 아닙니다: 파일 잠금/이어쓰기/rename 제약 — "진짜 파일시스템"을 기대하는 앱은 깨집니다
- 쓰기는 제한적(새 객체 생성 중심) — 읽기 위주 워크로드용이라 생각하세요
- 비용: S3 요청 과금 — 작은 파일 수백만 개 읽기는 GET 요금 폭탄 가능

## 5. 선택표 (lab-02에서 완성할 골격)

| 데이터 | 드라이버 | 근거 |
|--------|----------|------|
| DB (PostgreSQL 등) | **EBS** | 저지연 블록, RWO면 충분 (k8s 19) |
| 사용자 업로드 (여러 Pod 서빙) | **EFS** | RWX, AZ 무관 |
| ML 학습 데이터셋 (읽기) | **S3 CSI** | 대용량 저비용 순차 읽기 |
| 캐시/스크래치 | emptyDir/로컬 | 영속 불필요 (k8s 08) |
| 백업/아카이브 | S3 (CSI 아닌 SDK) | 앱이 직접 — 파일시스템 흉내 불필요 |

## 6. 소스/도구에서 확인하기

- EBS CSI: github.com/kubernetes-sigs/aws-ebs-csi-driver (파라미터 README)
- EFS CSI: github.com/kubernetes-sigs/aws-efs-csi-driver
- Mountpoint S3: github.com/awslabs/mountpoint-s3-csi-driver (제약 목록 필독)
- 스냅샷 API: kubernetes-csi/external-snapshotter

## 요약 카드

| 질문 | 답 |
|------|----|
| 세 드라이버 한 줄? | EBS=블록(RWO/AZ), EFS=파일(RWX), S3=객체(읽기 특화) |
| RWX가 필요하면? | EFS (EBS Multi-Attach 좌절의 답) |
| 디스크 풀 대응? | PVC 스펙 확장 — 온라인, 단 allowVolumeExpansion 필수 |
| 스냅샷 3종 세트? | SnapshotClass → VolumeSnapshot → dataSource 복원 |
| DB를 EFS에? | 금지 — 지연/랜덤IO 특성 불일치 |
| S3 CSI의 함정? | POSIX 아님(잠금/이어쓰기 X) + 요청 과금 |
