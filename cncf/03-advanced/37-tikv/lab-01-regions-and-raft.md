# Lab 01 — Region 자동 샤딩과 multi-Raft

21의 Raft가 데이터 저장으로 확장되는 것을 개념으로 확인하고, Region 자동 관리의 원리를 이해합니다.

전제: kind, kubectl (TiKV는 무거워 개념 중심).

## Step 1. 자동 샤딩 vs 명시적 샤딩 (36과 대비)

```bash
cat <<'EOF'
=== 두 샤딩 철학 (theory §2, 36) ===

[Vitess — 명시적]
  사용자: VSchema로 "users는 user_id로 100 샤드"
  리샤딩: "200 샤드로" 명시적 실행 (VReplication)
  → 사용자가 샤딩을 정의·관리

[TiKV — 자동]
  사용자: 아무것도 안 함
  시스템: 데이터가 쌓이면 Region이 자동 분할
          부하 불균형이면 PD가 Region 이동
  → 사용자는 Region을 모릅니다 (완전 자동)

트레이드오프:
  명시적(Vitess): 제어권 (샤딩 키를 신중히 설계)
  자동(TiKV): 편의 (샤딩을 신경 안 씀, but 제어 적음)
EOF
```

## Step 2. Region의 생명주기

```bash
cat <<'EOF'
=== Region 자동 관리 (theory §2) ===
Region = 연속 키 범위 [a, m) 의 데이터 조각 (~96MB)

split (분할):
  데이터가 쌓여 Region이 커짐 → 둘로 분할
  [a, z) → [a, m) + [m, z)
  → 핫스팟 완화 (한 Region에 부하 몰리면 나눔)

merge (병합):
  작은 Region들 → 합침 (오버헤드 감소)

balance (이동):
  PD가 노드 간 부하 불균형 감지 → Region 복제본 이동
  노드A(Region 100개) vs 노드B(Region 10개) → 재분배

→ 전부 자동, 사용자·앱 무관
  (36의 Vitess 리샤딩이 명시적 실행인 것과 대비)
EOF
```

## Step 3. multi-Raft — 21의 Raft를 수만 개

```bash
cat <<'EOF'
=== 각 Region이 Raft 그룹 (theory §3, 21) ===
etcd(21): 하나의 Raft 그룹
  클러스터 메타데이터(작은 데이터)를 3~5 노드가 Raft로 복제

TiKV: 수만 개의 Raft 그룹
  각 Region이 독립 Raft 그룹 (3 복제본)
  Region [a,m) → 노드1(리더)·노드2·노드3
  Region [m,z) → 노드2(리더)·노드3·노드1
  → 리더가 Region마다 분산 (부하 분산)

쓰기 (21의 Raft 그대로):
  Region 리더가 로그 append + 과반(2/3) 복제 → 커밋
  → 21에서 배운 쿼럼·리더·로그가 데이터에

스케일 도전:
  수만 그룹의 하트비트·선거 → batching, hibernation(유휴 Region)
  → etcd(단일 그룹)에 없던 문제

★ 21의 "fsync가 클러스터를 정한다":
  각 Region의 Raft 로그가 디스크(RocksDB)에
  → 저장 엔진 성능이 TiKV 성능의 핵심 (21의 디스크 교훈)
EOF
```

## Step 4. PD — 두뇌 (Vitess의 VTctld+Topology 자동화)

```bash
cat <<'EOF'
=== PD (theory §4) ===
Placement Driver가 하는 일:
  ① Region 메타데이터: 어느 Region이 어느 노드에 (라우팅)
  ② 스케줄링: split/merge/balance 결정
  ③ TSO(Timestamp Oracle): 전역 타임스탬프 (트랜잭션 순서)

Vitess 대비:
  Vitess: VTctld(관리, 사람이 리샤딩 실행) + Topology(메타데이터)
  TiKV: PD(자동 스케줄링 + 메타데이터 + TSO)
  → PD가 더 자동화 (사람 개입 적음)

PD 자체:
  etcd 기반 (21) — PD도 Raft로 자기 상태 복제
  → PD가 SPOF (21의 etcd, 36의 Topology와 같은 교훈)
  → PD의 HA·성능이 클러스터의 전제
EOF
```

## Step 5. 분산 트랜잭션 — Percolator (21의 MVCC 확장)

```bash
cat <<'EOF'
=== 분산 트랜잭션 (theory §5, 21) ===
TiKV의 트랜잭션: Percolator 모델 (Google)
  2PC(2단계 커밋) + MVCC
  TSO(PD)가 전역 타임스탬프 → 트랜잭션 순서 결정

MVCC (21의 etcd MVCC와 같은 계열):
  키의 여러 버전 (타임스탬프별)
  → 스냅샷 격리, 과거 읽기
  → 21에서 etcd MVCC를 배운 것이 데이터 저장으로

Vitess와 대비:
  Vitess: 크로스 샤드 트랜잭션이 부담 (2PC를 신중히, 성능 주의)
  TiKV: 분산 트랜잭션이 설계에 내장 (여러 Region에 걸쳐 자연스럽게)
  → "처음부터 분산" 설계의 이점 (트랜잭션이 1급)
EOF
```

## Step 6. 산출물

```markdown
# TiKV 내부 카드
- Region: 연속 키 범위 조각 — 자동 split/merge/balance (사용자 투명)
- multi-Raft: 각 Region이 21의 Raft 그룹 (수만 개, 스케일 도전)
- PD: 메타데이터·스케줄러·TSO — Vitess VTctld+Topology의 자동화판
- 트랜잭션: Percolator(2PC+MVCC) — 분산 내장 (21의 MVCC 확장)
- 21 연결: Raft(복제)·MVCC(버전)·디스크(fsync)가 데이터 저장으로
- PD가 SPOF (21 etcd·36 Topology 교훈 반복)
```

## 정리

lab-02에서 Vitess와 대비하고 판단합니다. 유지.
