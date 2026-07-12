# 36 — 백업과 DR: 지워도 되살아나는 클러스터

> 모듈 22의 etcd 스냅샷은 "클러스터 전체 되감기"였습니다 — 그런데 EKS에선 etcd가 AWS 소관이고, 현실의 사고는 "ns 하나를 실수로 지웠다"다. 그 간극을 메우는 도구가 Velero입니다: 리소스 단위 선택 백업/복구, 볼륨 데이터까지, 그리고 그 위에 세우는 RTO/RPO 기반 DR 설계.

## 학습 목표

1. etcd 스냅샷과 Velero의 분업(전체 되감기 vs 선택 복구)을 구분합니다
2. Velero를 설치하고 ns를 **실제로 지웠다가 되살립니다**
3. 볼륨 백업 2방식(CSI 스냅샷 vs 파일 백업)과 DB 정합성 문제를 압니다
4. RPO/RTO로 서비스별 DR 티어를 설계합니다
5. "백업 완료 ≠ 복구 가능" — Game Day(복구 훈련)를 절차로 만듭니다

## 선행: 모듈 08(PVC·Pod Identity), 19(PDB·StatefulSet), 20(cron), 22(etcd), 30(Operator 패턴) · 환경: 공유 EKS
## ⚠️ 비용: S3 저장 + EBS 스냅샷 — cleanup.sh가 과금 리소스부터 지웁니다

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-velero-backup.md](./lab-01-velero-backup.md) — 설치 → 백업 → 삭제 → 복구
3. [lab-02-volume-dr.md](./lab-02-volume-dr.md) — 볼륨 데이터 복구, 스케줄, DR 워크시트
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh` (★ 스냅샷 잔재 확인까지)

소요: 이론 1h + 실습 2.5h
