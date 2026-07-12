# 19 — StatefulSet: 상태 있는 워크로드

> Deployment가 못 푸는 문제 — "각자 자기 디스크와 고정 신원이 필요한 Pod들"(DB, Kafka, etcd류) — 의 공식 해법.

## 학습 목표

1. Deployment로 DB를 못 돌리는 이유 3가지를 정확히 말합니다
2. StatefulSet의 3대 보장(고정 이름/개별 스토리지/순서)을 실습으로 확인합니다
3. Headless Service + 멤버 DNS(`db-0.db...`)의 조합을 다룹니다
4. volumeClaimTemplates와 "PVC는 남는다" 동작을 이해합니다
5. 업데이트 전략(partition 카나리)과 강제 삭제의 위험을 압니다

## 선행: 모듈 04, 08, 16(Headless) · 환경: 공유 EKS + EBS CSI(모듈 08에서 설치)
## 비용: EBS 1GiB × replicas (실습 후 정리)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-identity-storage.md](./lab-01-identity-storage.md) — 신원/스토리지 보장 검증
3. [lab-02-ordering-updates.md](./lab-02-ordering-updates.md) — 순서, partition 업데이트
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2h
