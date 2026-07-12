# 10 — 스토리지 CSI: EBS, EFS, S3의 분업

> k8s 08(스토리지 기초)의 EKS 완성판. 세 드라이버의 성격 차이(블록/파일/객체), 스냅샷과 온라인 확장 같은 "운영 동작", 그리고 워크로드별 선택표까지.

## 학습 목표

1. CSI 구조(controller/node 플러그인)를 EKS 실물로 재확인합니다 (k8s 08 복습)
2. EBS CSI: gp3 파라미터, **VolumeSnapshot**(백업/복제), **온라인 확장**을 수행합니다
3. EFS CSI: RWX(여러 Pod 동시 마운트)와 access point 동적 프로비저닝을 다룹니다
4. Mountpoint S3 CSI의 용도(대용량 읽기)와 한계를 압니다
5. "이 데이터는 어느 드라이버에?"의 결정표를 만듭니다

## 선행: k8s 08/19(PVC·StatefulSet), eks 09(드라이버 권한) · 환경: 공유 EKS (EBS/EFS 과금 주의)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-ebs-snapshot-resize.md](./lab-01-ebs-snapshot-resize.md) — EBS 운영 동작 3종
3. [lab-02-efs-rwx.md](./lab-02-efs-rwx.md) — EFS RWX + 선택표 완성
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh` (★ EFS/스냅샷 과금)

소요: 이론 1h + 실습 2h
