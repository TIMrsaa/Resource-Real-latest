# Lab 01 — 샤딩 구조와 쿼리 라우팅

Vitess는 무거우므로 이 랩은 개념 확인 + Vitess Operator 구조 관찰 중심입니다. 샤딩 키가 왜 쿼리 성능을 정하는지를 이해합니다.

전제: kind, kubectl, helm (또는 vtctldclient 개념).

## Step 1. 샤딩 없는 세계 vs 샤딩된 세계

```bash
cat <<'EOF'
=== 앱이 샤딩할 때 vs Vitess (theory §1·§2) ===

[앱이 샤딩]
  # 모든 쿼리에 샤딩 로직
  shard = user_id % 100
  conn = connections[shard]
  result = conn.query("SELECT * FROM users WHERE user_id = ?", user_id)
  # 크로스 샤드? 100개 커넥션에 각각 쿼리하고 병합... 지옥

[Vitess]
  # 앱은 그냥 MySQL에 쿼리 (샤딩 모름)
  result = vtgate.query("SELECT * FROM users WHERE user_id = 123")
  # VTGate가 user_id=123의 샤드로 라우팅 (투명)
  # 크로스 샤드도 VTGate가 scatter-gather

→ 샤딩 복잡성이 앱에서 사라지고 Vitess가 흡수
  (03 CSI·29 Dapr처럼 복잡성을 추상 뒤로)
EOF
```

## Step 2. Vitess Operator 설치 (또는 구조 확인)

```bash
kind create cluster --name vitess -q

# Vitess Operator (PlanetScale) — 개념 확인
kubectl apply -f https://raw.githubusercontent.com/planetscale/vitess-operator/main/deploy/operator.yaml 2>/dev/null || \
  echo "(Operator 설치 — 실제 Vitess 클러스터는 무거워 구조 이해 중심)"
sleep 15
kubectl get pods 2>/dev/null | head -5
kubectl get crd 2>/dev/null | grep planetscale | head -4
```

## Step 3. 아키텍처 지도

```bash
cat <<'EOF'
=== Vitess 컴포넌트 (theory §2) ===
앱 ──MySQL 프로토콜──▶ VTGate ──▶ VTTablet ──▶ MySQL(샤드)

VTGate:   프록시 — 앱에 하나의 MySQL, 쿼리를 샤드로 라우팅
          (23의 Envoy처럼 프록시, MySQL 프로토콜)
VTTablet: 각 MySQL 앞의 에이전트 — 쿼리·헬스·백업·복제 관리
MySQL:    실제 데이터 (샤드마다 primary + replica들)
Topology: 클러스터 메타데이터 (etcd — 21처럼)
          어떤 샤드·태블릿, 누가 primary인가
VTctld:   관리 (리샤딩·스키마 변경 오케스트레이션)

→ K8s 오퍼레이터(08)가 이 모든 것을 CRD로:
  VitessCluster → keyspace → shard → tablet
EOF
```

## Step 4. VSchema와 VIndex — 라우팅의 두뇌

```bash
cat <<'EOF'
=== 어떻게 샤드를 고르나 (theory §3) ===
VSchema: "이 테이블이 어떻게 샤딩되나"
{
  "sharded": true,
  "vindexes": {
    "hash": { "type": "hash" }        # 샤딩 함수
  },
  "tables": {
    "users": {
      "column_vindexes": [
        { "column": "user_id", "name": "hash" }   # user_id로 샤딩
      ]
    }
  }
}

VIndex 종류:
  hash: user_id를 해시 → 균등 분산 (가장 흔함)
  lookup: 별도 테이블로 매핑 (email → user_id → 샤드, secondary)

라우팅:
  WHERE user_id = 123 → hash(123) → 특정 샤드 하나
EOF
```

## Step 5. ★ 샤딩 키가 쿼리 성능을 정합니다

```bash
cat <<'EOF'
=== 투명하지만 완전 투명은 아닙니다 (theory §3) ===

[좋은 쿼리 — 샤딩 키 사용]
  SELECT * FROM users WHERE user_id = 123
  → hash(123) → 샤드 하나로 (빠름)

[나쁜 쿼리 — 샤딩 키 없음]
  SELECT * FROM users WHERE email = 'a@b.com'
  → email로는 샤드를 모름 → 모든 샤드에 쿼리 (scatter-gather!)
  → 100 샤드면 100개 쿼리 → 느림, 부하

[집계 쿼리]
  SELECT COUNT(*) FROM users WHERE created > '2026-01-01'
  → 모든 샤드에서 세고 VTGate가 합산 (scatter-gather)

★ 핵심: Vitess가 샤딩을 흡수하지만, 쿼리 설계는 샤딩 키를 고려해야
  - 자주 쓰는 쿼리의 WHERE에 샤딩 키를 (단일 샤드 라우팅)
  - scatter-gather는 불가피하지만 최소화
  - lookup VIndex로 secondary 접근 경로
  → 앱이 완전히 무지할 순 없습니다 (추상의 한계 — 29의 이식성 한계와 같은 계열)
EOF
```

## Step 6. Topology — Vitess의 etcd (21과 연결)

```bash
cat <<'EOF'
=== Topology Service (theory §2, 21) ===
Vitess의 클러스터 상태를 저장 (etcd 또는 ZooKeeper):
  - 어떤 keyspace·샤드·태블릿이 있나
  - 각 샤드의 primary는 누구인가
  - VSchema

→ 21에서 배운 etcd의 역할과 유사:
  분산 시스템의 "진실의 원천"
  Topology가 아프면 Vitess가 아픕니다 (etcd가 아프면 K8s가 아프듯)
  → Topology의 HA·백업이 Vitess 운영의 핵심 (21의 교훈)
EOF
```

## Step 7. 산출물

```markdown
# Vitess 샤딩 카드
- 앱 → VTGate(하나의 MySQL로 보임) → 샤드로 라우팅
- 컴포넌트: VTGate(라우팅)·VTTablet(샤드)·MySQL·Topology(etcd)·VSchema
- VSchema/VIndex: 샤딩 키 → 샤드 매핑 (hash/lookup)
- 샤딩 키 있으면 단일 샤드(빠름), 없으면 scatter-gather(느림)
- 쿼리 설계가 샤딩 키를 고려해야 (완전 투명 아님)
- Topology = Vitess의 etcd (21) — HA·백업 핵심
```

## 정리

lab-02에서 리샤딩과 판단을 다룹니다. 유지.
