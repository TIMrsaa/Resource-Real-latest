# Lab 02 — 리샤딩(무중단 데이터 이동)과 도입 판단

Vitess의 킬러 기능(무중단 리샤딩)의 원리를 이해하고, 09의 판단이 극대화되는 지점과 도입 판단을 정리합니다.

전제: lab-01의 개념 이해.

## Step 1. 리샤딩 문제 — 전통 방식의 악몽

```bash
cat <<'EOF'
=== 샤드를 늘려야 할 때 (theory §4) ===
100 샤드가 부족 → 200 샤드로 (데이터 절반씩 이동)

전통(앱 샤딩):
  1. 앱을 멈춥니다 (다운타임)
  2. user_id % 100 → user_id % 200 으로 샤딩 로직 변경
  3. 데이터를 수동으로 재배치 (절반이 새 샤드로 이동)
  4. 검증하고 앱 재시작
  → 다운타임 + 위험 + 수동 작업 = 악몽
  → 그래서 많은 조직이 리샤딩을 미루다 벽에 부딪힘
EOF
```

## Step 2. Vitess 리샤딩 — VReplication

```bash
cat <<'EOF'
=== 무중단 리샤딩 (theory §4) ===
Vitess의 리샤딩:
  1. 새 샤드 생성 (빈 상태)
  2. VReplication: 기존 샤드 → 새 샤드로 데이터 온라인 복제
     (앱은 계속 기존 샤드에 읽고 쓰는 중)
  3. 복제가 따라잡으면 (기존과 새 샤드가 동기화)
     → 트래픽 전환: 읽기 먼저 (SwitchReads), 쓰기 나중 (SwitchWrites)
  4. 검증 후 기존 샤드 정리

→ 앱 무중단! Vitess가 데이터 이동을 오케스트레이션
  (17의 Progressive Delivery처럼 점진 전환 — 읽기→쓰기)

VReplication (Vitess의 핵심 엔진):
  샤드 간 데이터 흐름을 관리
  용도: 리샤딩, 다른 DB → Vitess 마이그레이션, 물질화 뷰
  → "데이터를 온라인으로 옮기는 능력"이 Vitess의 진짜 가치
EOF
```

## Step 3. 왜 이것이 어려운가 — 09의 극대화

```bash
cat <<'EOF'
=== Vitess = 가장 스테이트풀 (theory §5, 09) ===
09의 스테이트풀 판단 프레임이 최대로 적용:

① 관리형 대안?
   PlanetScale (Vitess 기반 관리형!), Aurora, TiDB Cloud
   → 대부분 관리형이 낫습니다 (운영 복잡도 회피)

② 오퍼레이터 Level?
   Vitess Operator — 리샤딩·백업·페일오버 자동화 수준 확인 (08)

③ 스토리지?
   각 샤드가 블록 스토리지 (05) — 수백 샤드 × (primary+replica)
   = MySQL 인스턴스 수천 개의 스토리지

④ 사람?
   MySQL 운영 + 분산 시스템 + Vitess 특화 = 3중 지식
   "새벽 3시에 샤드 하나의 primary가 죽으면?" 대응 가능한가

⑤ K8s 함정?
   각 VTTablet 안티어피니티, primary 재선출, Topology(etcd) 관리
   → 09의 모든 함정이 수백 샤드 규모로

→ Vitess는 "가장 무거운 스테이트풀" — 09의 판단이 극대화
EOF
```

## Step 4. 도입 판단 — 단일 DB의 벽

```bash
cat <<'EOF'
=== 언제 Vitess인가 (theory §6) ===

Vitess가 필요한 경우:
  ✅ 단일 MySQL의 벽을 실제로 만남
     - 쓰기 처리량 한계 (복제본은 읽기만 분산)
     - 데이터 크기 (단일 서버에 안 들어감)
     - 운영 한계 (거대 단일 DB의 백업·스키마 변경)
  ✅ MySQL 호환 필수 (기존 앱·생태계·SQL)
  ✅ 초대형 규모 (YouTube·Slack급)

Vitess가 아닌 경우 (대부분):
  ❌ 단일 DB로 충분 (수직 확장·복제본·캐싱으로 여유)
  ❌ 관리형이 답:
     PlanetScale (Vitess 관리형 — 복잡도 없이 Vitess)
     Aurora (AWS 관리형 MySQL, 상당한 스케일)
     TiDB Cloud (37 — 분산 SQL)
  ❌ MySQL 호환 불필요 → 다른 분산 DB (TiKV/TiDB — 37, CockroachDB)

판단 순서 (09):
  1. 단일 DB로 정말 안 되나요? (측정 — 쓰기 처리량·크기)
  2. 안 되면 관리형으로? (PlanetScale이 Vitess 복잡도 흡수)
  3. 자체 운영이 정당한가? (온프레·규제·비용 + 3중 지식)
  → 대부분 2에서 끝납니다
EOF
```

## Step 5. Vitess vs 다른 분산 DB (37 예고)

```bash
cat <<'EOF'
=== 분산 DB 선택 (09, 37 예고) ===
| | Vitess | TiDB/TiKV(37) | CockroachDB |
|---|---|---|---|
| 기반 | MySQL 샤딩 | 자체 분산 (Raft) | 자체 분산 |
| 호환 | MySQL | MySQL 호환 | PostgreSQL 호환 |
| 샤딩 | 명시적(VSchema) | 자동 | 자동 |
| 성숙 | YouTube 검증 | 성장 | BSL 라이선스 주의(01) |
| 자리 | 기존 MySQL 확장 | 새 분산 SQL | 새 분산 SQL |

선택:
  기존 MySQL을 확장 → Vitess (호환·점진)
  새로 분산 SQL → TiDB(37)·CockroachDB (자동 샤딩)
  → 37에서 TiKV를 배우고 대비
EOF
```

## Step 6. 산출물

```markdown
# Vitess 판단 카드
## 리샤딩 (킬러 기능)
- VReplication으로 온라인 데이터 이동 → 무중단
- 읽기→쓰기 점진 전환 (17의 Progressive Delivery 계열)
- "데이터를 온라인으로 옮기는 능력"이 진짜 가치

## 09 극대화 (가장 스테이트풀)
- 관리형(PlanetScale) → 오퍼레이터 → 스토리지 → 3중 지식 → K8s 함정
- 수백 샤드 규모로 모든 판단이 확대

## 판단
- 단일 DB의 벽을 실제로 만났나요? (측정)
- 만났으면 관리형(PlanetScale)부터 (복잡도 흡수)
- 자체 운영은 온프레·규제·비용 + 3중 지식
- 대부분은 관리형에서 끝 (35의 원칙: 벽을 만났으면)
```

## 정리

```bash
bash cleanup.sh
```
