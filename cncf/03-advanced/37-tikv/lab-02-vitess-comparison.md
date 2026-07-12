# Lab 02 — Vitess와 설계 대비, 그리고 분산 DB 판단

36과 37을 나란히 놓아 두 분산 DB 철학을 정리하고, 09의 판단으로 선택합니다.

전제: lab-01의 개념 이해, 36의 Vitess 지식.

## Step 1. 같은 문제, 두 철학

```bash
cat <<'EOF'
=== 단일 DB의 벽, 두 답 (theory §6) ===
공통 문제: 단일 DB의 벽 (쓰기 처리량·데이터 크기·운영)

[Vitess(36)] — 기존 MySQL을 확장
  "이미 MySQL을 쓰니 그것을 샤딩으로 늘리자"
  명시적 샤딩(VSchema), MySQL 복제, 크로스 샤드 부담

[TiKV/TiDB(37)] — 처음부터 분산
  "분산이 필요하면 처음부터 분산 설계된 것을"
  자동 샤딩(Region), Raft 복제, 분산 트랜잭션 내장

→ 확장이냐 재설계냐
EOF
```

## Step 2. 설계 대비표

```bash
cat <<'EOF'
| 축 | Vitess(36) | TiKV/TiDB(37) |
|----|-----------|---------------|
| 출발 | 기존 MySQL | 처음부터 분산 |
| 샤딩 | 명시적(VSchema, 사용자 정의) | 자동(Region, 시스템) |
| 복제 | MySQL 복제 | Raft(21) |
| 트랜잭션 | 크로스 샤드 부담 | 분산 내장(Percolator) |
| 호환 | MySQL 직접 | MySQL(TiDB SQL 계층) |
| 리샤딩 | 명시적(VReplication) | 자동(Region split/balance) |
| 제어 | 높음(샤딩 설계) | 낮음(자동, 편의) |
| 성숙 | YouTube(오래) | PingCAP(성장) |
| 관리형 | PlanetScale | TiDB Cloud |

선택:
  기존 MySQL 자산 크고 확장 → Vitess (점진·호환·제어)
  새 분산 SQL, 자동화·분산 트랜잭션 원함 → TiDB/TiKV
EOF
```

## Step 3. 21의 지식이 데이터 저장으로 — 종합

```bash
cat <<'EOF'
=== 21(etcd)의 개념이 확장되는 곳 (theory §3·§4·§5) ===
21에서 배운 것 → 여기서:

Raft(합의):
  21: etcd가 클러스터 메타데이터를 Raft로 (단일 그룹)
  37: TiKV가 데이터를 Region마다 Raft로 (multi-Raft, 수만 그룹)

MVCC(버전):
  21: etcd의 리비전 (resourceVersion)
  37: TiKV의 트랜잭션 버전 (Percolator)

디스크(fsync):
  21: etcd fsync가 K8s를 정합니다
  37: TiKV의 RocksDB 성능이 TiKV를 정합니다

etcd 자체:
  37: PD가 etcd 기반 (메타데이터 복제)

→ 21의 분산 시스템 원리가 데이터베이스로 일반화
  "합의·버전·디스크·SPOF"는 분산 상태 시스템의 공통 언어
EOF
```

## Step 4. 09의 판단 — 여전히 관리형 우선

```bash
cat <<'EOF'
=== 분산 DB 도입 판단 (09, 36과 동일) ===
1. 단일 DB로 정말 안 되나요? (측정)
   → 대부분 여기서 끝 (단일 DB로 충분)

2. 안 되면 어떤 분산 DB?
   기존 MySQL 확장 → Vitess/PlanetScale
   새 분산 SQL → TiDB/TiKV/TiDB Cloud
   PostgreSQL 계열 → CockroachDB (BSL 주의 — 01)

3. 자체 운영 vs 관리형?
   → 관리형 우선 (TiDB Cloud, PlanetScale)
   → 자체는 온프레·규제·비용 + 분산 시스템 3중 지식(09)

★ TiKV/TiDB도 09의 극단적 스테이트풀:
  PD SPOF, 각 Region의 Raft, RocksDB 저장 엔진, 백업
  → 관리형이 이 복잡도를 흡수 (36의 사고 사례 교훈)
EOF
```

## Step 5. TiKV 독립 사용 — KV로도

```bash
cat <<'EOF'
=== TiKV는 TiDB 없이도 (theory §1) ===
TiKV = 분산 트랜잭션 KV (독립)
  TiDB(SQL) 없이 KV 저장소로 직접 사용 가능
  → 분산 KV가 필요하지만 SQL 불필요할 때

용도:
  메타데이터 저장 (etcd보다 큰 규모)
  분산 KV 애플리케이션
  다른 시스템의 스토리지 계층

→ etcd(21, 작은 메타데이터) vs TiKV(대규모 분산 KV)
  둘 다 Raft KV지만 스케일·용도가 다릅니다
EOF
```

## Step 6. 산출물 — 분산 DB 종합

```markdown
# 분산 DB 판단 (09·36·37 종합)
## 두 철학
- Vitess(36): 기존 MySQL 확장, 명시적 샤딩, 제어
- TiKV/TiDB(37): 처음부터 분산, 자동 샤딩(Region), 편의

## 21의 확장
- Raft·MVCC·디스크·SPOF가 메타데이터(etcd)에서 데이터(TiKV)로
- "합의·버전·디스크"는 분산 상태 시스템의 공통 언어

## 판단 (09)
- 단일 DB로 안 되나요? → 대부분 여기서 끝
- 안 되면: 기존 MySQL→Vitess, 새 분산→TiDB
- 관리형 우선 (PlanetScale/TiDB Cloud) — 복잡도 흡수
- 자체 운영은 극단적 스테이트풀 (09 최대)
```

## 정리

```bash
bash cleanup.sh
```
