# 22 — etcd 심층: Raft, MVCC, watch, 운영

> 클러스터의 유일한 진실 원본을 해부합니다. EKS에서는 etcd가 숨겨져 있으므로, **로컬에 etcd를 직접 띄워** 내부를 만집니다 — 이 모듈은 예외적으로 로컬 실습입니다.

## 학습 목표

1. Raft 합의(리더 선출, 정족수)를 3노드 로컬 클러스터로 체험합니다
2. MVCC와 revision — resourceVersion의 출처 — 를 etcdctl로 확인합니다
3. watch가 etcd 레벨에서 어떻게 동작하는지 봅니다
4. compaction/defrag의 필요성과 "DB 크기 한도 초과" 장애를 재현합니다
5. 스냅샷 백업/복원을 수행합니다 (EKS가 대신해주는 일의 실체)
6. K8s 객체가 etcd에 어떤 키/형식으로 저장되는지 압니다

## 선행: 모듈 21 · 환경: **로컬** (Docker 또는 WSL2에 etcd 바이너리) · 비용: 무료

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-raft-mvcc.md](./lab-01-raft-mvcc.md) — 3노드 클러스터, 리더 죽이기, revision 관찰
3. [lab-02-maintenance.md](./lab-02-maintenance.md) — compaction/defrag/쿼터 초과/백업복원
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md)

소요: 이론 1.5h + 실습 2h
