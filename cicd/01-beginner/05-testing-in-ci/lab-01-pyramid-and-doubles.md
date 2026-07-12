# Lab 01 — 피라미드 세 층을 CI에 배치하기

같은 기능을 세 층으로 테스트해보고 — 실행 시간, 실패 시 원인 특정력, 격리 방법의 차이를 실측합니다. 그리고 통합 테스트를 CI에서 재현 가능하게 만드는 두 방법을 비교합니다.

## Step 1. 테스트 대상 — 외부 의존이 있는 코드

```bash
mkdir -p ~/ci-lab/testing/{app,tests} && cd ~/ci-lab/testing
git init -q && git config user.email l@e.com && git config user.name L

cat > app/store.py <<'EOF'
"""주문 저장소 — DB(외부 세계)에 의존합니다."""

class OrderStore:
    def __init__(self, db):          # ★ 의존성 주입 — 테스트 가능성의 문법 (eks 28·29의 그 사상)
        self.db = db

    def place(self, user_id, amount):
        if amount <= 0:
            raise ValueError("amount must be positive")
        return self.db.insert("orders", {"user": user_id, "amount": amount})

    def total_for(self, user_id):
        rows = self.db.query("SELECT amount FROM orders WHERE user = ?", user_id)
        return sum(r[0] for r in rows)
EOF
touch app/__init__.py

cat > app/pgdb.py <<'EOF'
"""진짜 DB 어댑터 (통합 테스트의 대상)."""
import psycopg

class PgDb:
    def __init__(self, dsn):
        self.conn = psycopg.connect(dsn, autocommit=True)
        with self.conn.cursor() as c:
            c.execute("CREATE TABLE IF NOT EXISTS orders (id serial, \"user\" text, amount int)")

    def insert(self, table, row):
        with self.conn.cursor() as c:
            c.execute('INSERT INTO orders ("user", amount) VALUES (%s, %s) RETURNING id',
                      (row["user"], row["amount"]))
            return c.fetchone()[0]

    def query(self, _sql, user_id):
        with self.conn.cursor() as c:
            c.execute('SELECT amount FROM orders WHERE "user" = %s', (user_id,))
            return c.fetchall()
EOF
```

## Step 2. 1층 — 단위 테스트 + Fake (Mock이 아니라)

```bash
cat > tests/test_unit.py <<'EOF'
"""Fake DB — 간단하지만 진짜로 동작하는 구현 (theory §2)."""
import pytest
from app.store import OrderStore


class FakeDb:
    def __init__(self):
        self.rows = []

    def insert(self, table, row):
        self.rows.append(row)
        return len(self.rows)

    def query(self, _sql, user_id):
        return [(r["amount"],) for r in self.rows if r["user"] == user_id]


def test_place_returns_id():
    store = OrderStore(FakeDb())
    assert store.place("alice", 100) == 1

def test_place_rejects_zero():
    store = OrderStore(FakeDb())
    with pytest.raises(ValueError):
        store.place("alice", 0)

def test_total_sums_only_user_orders():
    store = OrderStore(FakeDb())
    store.place("alice", 100); store.place("bob", 50); store.place("alice", 25)
    assert store.total_for("alice") == 125     # 행동을 검증합니다 (호출 횟수가 아니라)
EOF

pip install -q pytest 2>/dev/null
time python -m pytest -q tests/test_unit.py
```

예상: 3 passed, **수십 밀리초**. ✅ Fake는 "몇 번 호출됐나"(Mock의 관심)가 아니라 **"합계가 맞나"**(행동)를 검증합니다 — `OrderStore` 내부를 리팩터링해도 이 테스트는 살아남습니다.

## Step 3. 2층 — 통합 테스트 (진짜 Postgres)

```bash
cat > tests/test_integration.py <<'EOF'
import os, pytest
from app.pgdb import PgDb
from app.store import OrderStore

DSN = os.getenv("TEST_DSN")
pytestmark = pytest.mark.skipif(not DSN, reason="TEST_DSN 없음")

@pytest.fixture
def store():
    db = PgDb(DSN)
    with db.conn.cursor() as c:      # ★ 테스트 간 격리 (순서 의존 flaky 방지 — theory §4)
        c.execute("TRUNCATE orders")
    return OrderStore(db)

def test_persists_across_instances(store):
    store.place("alice", 300)
    assert store.total_for("alice") == 300

def test_sql_actually_filters(store):
    store.place("alice", 100); store.place("bob", 999)
    assert store.total_for("alice") == 100    # Fake는 이 SQL 버그를 못 잡습니다!
EOF
```

로컬에서 Postgres를 띄워 실행:

```bash
docker run -d --name pg-test -e POSTGRES_PASSWORD=test -p 5432:5432 postgres:17 >/dev/null
until docker exec pg-test pg_isready -q 2>/dev/null; do sleep 1; done   # ★ 헬스체크 대기
pip install -q psycopg[binary]
time TEST_DSN="postgresql://postgres:test@localhost:5432/postgres" python -m pytest -q tests/test_integration.py
docker rm -f pg-test >/dev/null
```

예상: 2 passed, **수 초**(컨테이너 시작 제외). ✅ 두 번째 테스트가 핵심입니다 — **Fake로는 절대 못 잡는 SQL 버그**를 통합 테스트가 잡습니다. 그래서 층이 나뉘어 있습니다.

## Step 4. CI 배치 — service container로 격리

```bash
mkdir -p .github/workflows
cat > .github/workflows/test.yml <<'EOF'
name: test
on: [push, pull_request]
permissions: { contents: read }

jobs:
  unit:                                # 빠르고 결정적 — 항상 먼저
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12", cache: pip }
      - run: pip install pytest
      - run: pytest -q tests/test_unit.py

  integration:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:17
        env: { POSTGRES_PASSWORD: test }
        ports: ["5432:5432"]
        options: >-                    # ★ 헬스체크 없으면 "DB 아직 안 떴는데 테스트 시작" flaky
          --health-cmd pg_isready
          --health-interval 5s
          --health-timeout 3s
          --health-retries 10
    env:
      TEST_DSN: postgresql://postgres:test@localhost:5432/postgres
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12", cache: pip }
      - run: pip install pytest "psycopg[binary]"
      - run: pytest -q tests/test_integration.py

  ci:                                  # 03의 수렴 잡 패턴
    if: always()
    needs: [unit, integration]
    runs-on: ubuntu-latest
    steps:
      - run: |
          [ "${{ needs.unit.result }}" = "success" ] && [ "${{ needs.integration.result }}" = "success" ]
EOF

cat > requirements-dev.txt <<'EOF'
pytest==8.3.4
psycopg[binary]==3.2.3
EOF
git add -A && git commit -qm "test: pyramid layers" 
gh repo create cicd-lab-testing --public --source=. --push >/dev/null
sleep 70
gh run list --limit 1
```

✅ 잡이 나뉘어 있으므로 **단위 테스트 실패는 20초 만에** 보고됩니다 — 통합 잡이 컨테이너를 띄우는 동안에도.

## Step 5. 격리의 두 방식 비교

```markdown
| | service container | testcontainers |
|---|---|---|
| 수명 소유자 | 잡(러너) | 테스트 코드 |
| 로컬 재현 | docker run을 따로 (drift 위험) | **같은 코드**로 동일 |
| 시작 대기 | health 옵션 필수 | 라이브러리가 처리 |
| 여러 버전 매트릭스 | 잡 매트릭스로 | 코드에서 파라미터화 |
| 필요 조건 | Actions 기능 | Docker 소켓 접근 |
```

권장: **로컬-CI 일관성이 중요하면 testcontainers**, 단순한 단일 의존이면 service container. 어느 쪽이든 헬스 대기가 flaky의 첫 번째 방지선입니다.

## Step 6. 실패 시 원인 특정력 비교 (피라미드의 이유)

일부러 버그를 심어보세요:

```bash
sed -i 's/return sum(r\[0\] for r in rows)/return sum(r[0] for r in rows) + 1/' app/store.py
python -m pytest -q tests/test_unit.py 2>&1 | tail -4
git checkout app/store.py
```

단위 테스트는 **어느 함수의 어느 줄**인지 즉시 말해줍니다. 같은 버그를 e2e로만 잡으면 "체크아웃 페이지 금액이 이상함"에서 시작해야 합니다 — theory §1의 표가 실감됩니다.

## 정리

```bash
docker rm -f pg-test 2>/dev/null || true
```

저장소는 lab-02에서 계속 사용.
