# 학습 가이드 — 두 가지 분산 DB 철학

## 36과 짝 — 확장이냐 재설계냐

36(Vitess)과 37(TiKV)은 같은 문제(단일 DB의 벽)를 정반대 철학으로 풉니다:

```
             Vitess(36)                    TiKV(37)
출발         기존 MySQL                     처음부터 분산 설계
샤딩         명시적 (VSchema, 사용자가 정의)  자동 (Region, 시스템이 관리)
복제         MySQL 복제                     Raft (21의 그것)
호환         MySQL                          TiDB로 MySQL 호환 (SQL 계층 별도)
철학         "기존 MySQL을 무한히 확장"       "분산을 처음부터 올바르게"
```

Vitess는 "이미 MySQL을 쓰니 그것을 확장하자"이고, TiKV는 "분산이 필요하면 처음부터 분산으로 설계된 것을 쓰자"입니다. 어느 것이 옳은가는 상황입니다 — 기존 MySQL 자산이 크면 Vitess, 새로 분산 SQL을 시작하면 TiKV/TiDB.

## 21의 Raft가 데이터 저장으로

21에서 etcd의 Raft를 배웠습니다 — 리더 선출, 로그 복제, 쿼럼. TiKV는 그 Raft를 **대규모 데이터 저장**에 씁니다:

```
etcd(21): 클러스터 메타데이터(작은 데이터)를 Raft로 복제
TiKV: 애플리케이션 데이터(TB급)를 Region 단위로 Raft 복제
  → 각 Region이 자기 Raft 그룹 (multi-Raft)
  → 수만 개의 Raft 그룹이 동시에
```

같은 Raft 알고리즘(21의 쿼럼·리더·로그)이지만 스케일이 다릅니다 — etcd는 하나의 Raft 그룹, TiKV는 수만 개. 21의 Raft 지식이 여기서 데이터 저장의 기반으로 재등장합니다.

## Region — 자동 샤딩의 단위

TiKV의 핵심 개념은 Region입니다:

```
Region = 연속된 키 범위 (예: [a, m))의 데이터 조각
  각 Region이 자기 Raft 그룹 (3 복제본)
  Region이 커지면 자동 분할 (split)
  부하 불균형이면 PD가 Region을 이동 (balance)
  → 사용자는 Region을 모릅니다 (자동)
```

Vitess의 샤드가 사용자가 정의하는 명시적 단위라면, TiKV의 Region은 시스템이 자동으로 나누고 옮기는 단위입니다. 이것이 "자동 샤딩"의 실체이고, PD(Placement Driver)가 그 오케스트레이션을 합니다(36의 VTctld보다 자동화 수준이 높습니다).

## 이 모듈의 자리

09의 데이터 지도에서 TiKV·Vitess를 소개했고, 36·37이 그 둘을 심층으로 대비합니다. 그리고 21의 Raft가 메타데이터(etcd)를 넘어 데이터 저장(TiKV)으로 확장되는 것을 봅니다. 09의 스테이트풀 판단은 여기서도 극대화되지만(분산 DB), TiKV/TiDB도 관리형(TiDB Cloud)이 있어 "자체 운영 vs 관리형"의 판단은 36과 같습니다.
