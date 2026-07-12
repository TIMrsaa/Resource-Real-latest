# 08 — 스토리지 기초: Volume, PV/PVC, StorageClass

> "컨테이너의 데이터는 사라진다"(모듈 01) 문제의 공식 해법. 임시 볼륨부터 EBS 동적 프로비저닝까지.

## 학습 목표

1. emptyDir/hostPath와 영속 볼륨의 차이를 압니다
2. PV(저장소) / PVC(신청서) / StorageClass(자판기) 3분할 설계의 의도를 설명합니다
3. EKS에서 EBS CSI 드라이버로 동적 프로비저닝을 실습합니다
4. Pod가 죽어도 데이터가 살아남는 것을 직접 검증합니다
5. accessModes, reclaimPolicy, 볼륨 확장을 다룹니다

## 선행: 모듈 03(emptyDir 경험), 07 · 환경: 공유 EKS
## 비용: EBS gp3 1GiB ≈ $0.001/h 수준 — 실습 후 cleanup 필수

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-ephemeral-volumes.md](./lab-01-ephemeral-volumes.md) — emptyDir/hostPath의 수명 실험
3. [lab-02-pvc-ebs.md](./lab-02-pvc-ebs.md) — EBS CSI 설치, PVC, 데이터 생존 검증, 확장
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2h
