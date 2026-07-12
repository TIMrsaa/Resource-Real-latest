# 21 — etcd 심층: 합의, 저장, 그리고 클러스터의 심장을 다루는 법

> 09의 지도에서 "선택이 아니라 전제"라고 했던 그 프로젝트. K8s의 모든 선언·상태·watch가 이 위에 있고, **etcd가 아프면 클러스터가 아픕니다**. 이 모듈은 세 축을 팝니다: Raft 합의(리더 선출·로그 복제·쿼럼이 왜 그 모양인지), MVCC 저장 엔진(리비전·컴팩션·디프래그가 왜 필요한지), 그리고 운영의 물리학(디스크 fsync 지연이 어떻게 클러스터 전체를 무너뜨리는지, 백업과 재해 복구). k8s 36의 백업이 여기서 원리로 되짚어집니다.

## 학습 목표

1. Raft의 세 요소(리더 선출·로그 복제·안전성)와 쿼럼 계산, 짝수 노드의 무의미함을 압니다
2. MVCC 저장 모델(리비전·keyspace·컴팩션·디프래그)을 이해하고 "DB space exceeded"를 재현·복구합니다
3. `wal_fsync_duration`이 왜 1번 운영 지표인지 알고, 디스크 지연이 API 서버로 번지는 경로를 압니다
4. 백업(snapshot)과 복구(단일 노드 재구성)를 직접 수행합니다
5. K8s 특유의 etcd 부하(watch, 큰 오브젝트, 이벤트)를 진단하고 줄입니다

## 선행: 09(지도), k8s(컨트롤 플레인·백업), 20(장애의 층) · 도구: kind, kubectl, etcdctl, docker
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-raft-and-mvcc.md](./lab-01-raft-and-mvcc.md) — 합의 관찰, 리비전·컴팩션·디프래그
3. [lab-02-backup-restore-and-load.md](./lab-02-backup-restore-and-load.md) — 스냅샷·복구, 부하와 지표
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2.5h
