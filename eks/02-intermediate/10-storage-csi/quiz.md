# 자가 점검 퀴즈

**Q1.** EBS/EFS/S3 CSI의 성격을 접근 모드·AZ·지연 관점에서 비교하세요.

**Q2.** VolumeSnapshot 3종 세트와 복원 절차는?

**Q3.** 온라인 확장의 명령, 전제 조건, 제약 3가지는?

**Q4.** "PVC는 Bound인데 Pod이 마운트에서 멈춤"(EFS) — 점검 2순위까지는?

**Q5.** EFS 동적 프로비저닝에서 access point의 역할은?

**Q6.** "DB를 EFS에"가 이중으로 틀린 이유는?

**Q7.** S3 CSI가 적합한 워크로드와 깨지는 워크로드는?

**Q8.** ① 업로드 파일(3 Pod 서빙) ② Postgres ③ 50TB 학습데이터 ④ 빌드 캐시 — 각각의 선택과 근거는?

---

## 정답

**A1.** EBS: RWO(한 노드), AZ 종속, 저지연 블록 — 빠른 단독 사용. EFS: RWX(다중 노드 동시), AZ 무관(리전), 지연 큼(NFS) — 공유 파일. S3 CSI: 파일시스템 흉내(POSIX 아님), 리전, 대용량 순차 읽기 특화.

**A2.** VolumeSnapshotClass(드라이버/정책) → VolumeSnapshot(대상 PVC 지정 — EBS 스냅샷 생성) → 새 PVC의 `dataSource`에 그 스냅샷 지정(복원 볼륨 생성). Velero의 CSI 모드가 이 체계의 자동화판(k8s 36).

**A3.** `kubectl patch pvc ... storage: <큰값>` — 무중단 온라인 확장. 전제: StorageClass의 `allowVolumeExpansion: true`. 제약: ① 축소 불가 ② EBS 동일 볼륨 6시간 쿨다운 ③ 파일시스템 확장까지 약간의 지연(완료는 pvc status로).

**A4.** ① 노드 SG에 NFS 2049 인바운드 허용 여부 ② Pod이 뜬 AZ에 mount target 존재 여부. (그다음: 드라이버 Pod 상태, access point/권한) — EFS 장애의 다수는 네트워크 배선.

**A5.** 하나의 EFS 파일시스템 안에서 PVC마다 전용 디렉터리+POSIX 신원(uid/gid)을 가진 진입점을 만들어 **격리된 동적 프로비저닝**을 가능케 함 — 파일시스템을 PVC 수만큼 만들지 않아도 됩니다.

**A6.** ① 아키텍처 오류: DB의 HA는 스토리지 공유가 아니라 DB 레벨 복제(WAL 등)로 — 같은 데이터 파일 동시 쓰기는 파손의 길 ② 성능 오류: EFS의 메타데이터 왕복/지연이 DB의 소량 랜덤 IO와 상극.

**A7.** 적합: ML 학습 데이터/로그 분석 등 대용량 **순차 읽기** 파이프라인. 깨짐: 파일 잠금·이어쓰기·rename·mmap 등 POSIX 의미론을 기대하는 앱, 작은 파일 대량 랜덤 접근(요청 과금+지연).

**A8.** ① EFS(RWX 필수) ② EBS gp3+StatefulSet(저지연 RWO — 또는 RDS) ③ S3 CSI(용량 단가+순차 읽기) ④ emptyDir(영속 불필요 — 빠르고 공짜).
