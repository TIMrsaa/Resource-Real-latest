# 이론 — 아키텍처, Region·자동 샤딩, multi-Raft, PD, 트랜잭션, 대비

> **🌱 17세 눈높이 비유: 자동 정리 창고**
> - **Vitess(36)** = 사서가 "A-F는 1관"이라고 미리 정한 도서관 (명시적 샤딩)
> - **TiKV** = 스스로 정리하는 창고 — 선반(Region)이 차면 자동으로 둘로 나누고, 한 선반이 붐비면 로봇(PD)이 물건을 옆 선반으로 옮깁니다
> - **Region** = 연속된 구역의 물건 조각 (책 A~M) — 이것이 자동 샤딩의 단위
> - **multi-Raft** = 각 선반(Region)마다 3개 사본과 투표 체계 (21의 Raft를 선반마다)
> - **PD(Placement Driver)** = 창고 관리 로봇 — 어느 선반이 어디 있나, 붐비면 재배치
> - **자동** = 사서(사용자)는 정리 방식을 몰라도 됩니다 — 창고가 알아서 (Vitess는 사서가 정함)

---

## 1. 아키텍처

```
[TiDB 스택]
  TiDB (SQL 계층 — MySQL 호환) ──▶ TiKV (KV 저장) ──▶ 데이터
                                      ↑
                                    PD (Placement Driver)

컴포넌트:
  TiKV 노드: 실제 데이터 저장 (Region들, 각 Region이 Raft 그룹)
             RocksDB 기반 저장 엔진
  PD:        메타데이터·스케줄러 — Region 위치, 밸런싱, 타임스탬프(TSO)
             (자체도 etcd 기반 — 21)
  TiDB:      SQL 계층 (선택) — MySQL 호환 파서·옵티마이저, stateless
             TiKV를 스토리지로 (TiKV는 독립 KV로도 쓰임)

★ TiKV = KV 저장, TiDB = 그 위의 SQL
  09에서 "TiKV는 TiDB의 스토리지 층"이라 한 것
```

## 2. Region — 자동 샤딩

```
Region = 연속된 키 범위의 데이터 (예: 키 [a, m))
  기본 크기 (예: ~96MB) → 넘으면 자동 분할(split)
  각 Region이 독립된 Raft 그룹 (3 복제본)

자동 관리:
  split: Region이 커지면 둘로 (핫스팟 완화)
  merge: 작은 Region들을 합침
  balance: PD가 부하 불균형 시 Region을 노드 간 이동
  → 사용자·앱은 Region을 모릅니다 (완전 자동)

Vitess와 대비:
  Vitess 샤드: 사용자가 VSchema로 명시적 정의, 리샤딩도 명시적 실행
  TiKV Region: 시스템이 자동 분할·이동 (투명)
  → "자동 샤딩" vs "명시적 샤딩"
```

## 3. multi-Raft — 21의 Raft를 데이터에

```
etcd(21): 하나의 Raft 그룹 (클러스터 메타데이터, 작은 데이터)
TiKV: 수만 개의 Raft 그룹 (각 Region이 하나)

각 Region의 Raft (21의 그 알고리즘):
  리더 선출, 로그 복제, 쿼럼 (3 복제본 → 2 쿼럼)
  쓰기: 리더 Region이 로그 append + 과반 복제 → 커밋
  → 21에서 배운 Raft가 데이터 저장에

multi-Raft의 도전:
  수만 그룹의 하트비트·선거를 효율적으로 (batching, hibernation)
  → etcd(단일 그룹)에 없던 스케일 문제
  ★ 21의 "fsync가 클러스터를 정한다"가 여기서도:
    각 Region의 Raft 로그가 디스크에 → 저장 엔진(RocksDB) 성능이 핵심
```

## 4. PD — 두뇌

```
PD(Placement Driver)가 하는 일:
  Region 메타데이터: 어느 Region이 어느 노드에 (라우팅)
  스케줄링: Region split/merge/balance 결정
  TSO(Timestamp Oracle): 전역 타임스탬프 (트랜잭션 순서 — 아래)
  → 36의 VTctld + Topology를 합친 자동화판

PD 자체:
  etcd 기반 (21) — PD도 Raft로 자기 상태 복제
  → PD가 SPOF ≈ Vitess Topology, K8s etcd (21의 교훈 반복)
```

## 5. 트랜잭션 — 분산 MVCC

```
TiKV의 분산 트랜잭션:
  Percolator 모델 (Google) 기반 — 2PC + MVCC
  TSO(PD)가 전역 타임스탬프 → 트랜잭션 순서
  → 여러 Region에 걸친 트랜잭션 (Vitess의 크로스 샤드보다 자연스러움)

MVCC (21의 etcd MVCC와 같은 계열):
  키의 여러 버전 (타임스탬프별)
  → 스냅샷 격리, 과거 읽기
  → 21에서 etcd MVCC를 배운 것이 여기서 데이터 저장으로

★ 분산 트랜잭션이 1급:
  Vitess: 크로스 샤드 트랜잭션이 부담 (2PC를 신중히)
  TiKV: 분산 트랜잭션이 설계에 내장 (Percolator)
  → "처음부터 분산" 설계의 이점
```

## 6. Vitess vs TiKV — 설계 대비 (36 완성)

| | Vitess(36) | TiKV/TiDB(37) |
|---|---|---|
| 출발 | 기존 MySQL 확장 | 처음부터 분산 |
| 샤딩 | 명시적(VSchema) | 자동(Region) |
| 복제 | MySQL 복제 | Raft(21) |
| 트랜잭션 | 크로스 샤드 부담 | 분산 내장(Percolator) |
| 호환 | MySQL(직접) | MySQL(TiDB SQL 계층) |
| 리샤딩 | 명시적(VReplication) | 자동(Region split/balance) |
| 성숙 | YouTube 검증(오래됨) | 성장(PingCAP) |
| 자리 | 기존 MySQL 자산 확장 | 새 분산 SQL |

```
선택:
  기존 MySQL이 크고 그것을 확장 → Vitess (점진·호환)
  새로 분산 SQL을 시작, 자동 샤딩·분산 트랜잭션 원함 → TiDB/TiKV
  → 둘 다 09의 판단(관리형 우선)이 적용
```

## 7. 소스/도구에서 확인하기

- TiKV: https://tikv.org/docs — architecture, Raft, Region
- TiDB: https://docs.pingcap.com — SQL layer
- Percolator: Google 논문 (분산 트랜잭션)
- 09(데이터)·21(etcd·Raft·MVCC)·36(Vitess) 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| TiKV vs Vitess? | 자동 샤딩·자체 분산 vs 명시적 샤딩·MySQL 확장 |
| Region? | 연속 키 범위 조각 — 자동 split/merge/balance (사용자 투명) |
| multi-Raft? | 각 Region이 21의 Raft 그룹 — 수만 개 동시 (스케일 도전) |
| PD? | 메타데이터·스케줄러·TSO — Vitess VTctld+Topology의 자동화판 |
| 트랜잭션? | Percolator(2PC+MVCC) — 분산 내장 (Vitess의 크로스 샤드 부담과 대비) |
| 21과 연결? | Raft(복제)·MVCC(버전)가 메타데이터(etcd)에서 데이터 저장으로 |
| 선택? | 기존 MySQL 확장(Vitess) vs 새 분산 SQL(TiDB) — 둘 다 관리형 우선 |
