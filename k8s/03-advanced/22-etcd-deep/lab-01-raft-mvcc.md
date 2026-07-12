# Lab 01 — 3노드 클러스터: 리더 죽이기와 MVCC

> **환경**: 로컬 Docker (WSL2). goreman 없이 docker compose로 3노드를 띄웁니다.

## Step 1. 3노드 etcd 클러스터 기동

```bash
mkdir -p ~/etcd-lab && cd ~/etcd-lab
cat > compose.yaml <<'EOF'
services:
  etcd1: &etcd
    image: gcr.io/etcd-development/etcd:v3.6.0
    command: >
      etcd --name etcd1
      --listen-client-urls http://0.0.0.0:2379 --advertise-client-urls http://etcd1:2379
      --listen-peer-urls http://0.0.0.0:2380 --initial-advertise-peer-urls http://etcd1:2380
      --initial-cluster etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380
      --initial-cluster-state new --initial-cluster-token lab
    ports: ["12379:2379"]
  etcd2:
    <<: *etcd
    command: >
      etcd --name etcd2
      --listen-client-urls http://0.0.0.0:2379 --advertise-client-urls http://etcd2:2379
      --listen-peer-urls http://0.0.0.0:2380 --initial-advertise-peer-urls http://etcd2:2380
      --initial-cluster etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380
      --initial-cluster-state new --initial-cluster-token lab
    ports: ["22379:2379"]
  etcd3:
    <<: *etcd
    command: >
      etcd --name etcd3
      --listen-client-urls http://0.0.0.0:2379 --advertise-client-urls http://etcd3:2379
      --listen-peer-urls http://0.0.0.0:2380 --initial-advertise-peer-urls http://etcd3:2380
      --initial-cluster etcd1=http://etcd1:2380,etcd2=http://etcd2:2380,etcd3=http://etcd3:2380
      --initial-cluster-state new --initial-cluster-token lab
    ports: ["32379:2379"]
EOF
docker compose up -d
alias e1='docker compose exec etcd1 etcdctl'
e1 endpoint status --cluster -w table
```

예상 출력:
```
+----------------+...+-----------+------------+
|    ENDPOINT    |...| IS LEADER | RAFT TERM  |
| http://etcd1...|...|   true    |     2      |    ← 리더 1명
| http://etcd2...|...|   false   |     2      |
| http://etcd3...|...|   false   |     2      |
+----------------+...+-----------+------------+
```

## Step 2. 리더 살해 → 자동 선출 관찰

```bash
# 리더가 누군지 확인 후 그 컨테이너를 죽입니다 (예: etcd1이 리더라고 가정)
LEADER=$(e1 endpoint status --cluster -w json | python3 -c "
import json,sys; d=json.load(sys.stdin)
for ep in d:
    if ep['Status']['leader']==ep['Status']['header']['member_id']: print(ep['Endpoint'])" | sed 's|http://||;s|:2379||')
echo "leader: $LEADER"
docker compose stop $LEADER

# 남은 노드에서 상태 확인 (etcd2 기준)
docker compose exec etcd2 etcdctl endpoint status --cluster -w table 2>/dev/null
```

예상: 수 초 내 **다른 노드가 IS LEADER true**, RAFT TERM이 +1 (선거가 있었다는 증거). 그리고:

```bash
# 2/3 생존 = 정족수 유지 → 쓰기 정상
docker compose exec etcd2 etcdctl put /test "still writable"; docker compose exec etcd2 etcdctl get /test
```

## Step 3. 정족수 상실 → 읽기 전용 좀비

```bash
# 한 대 더 죽입니다 (1/3 생존)
docker compose stop etcd3 2>/dev/null || docker compose stop etcd1
docker compose exec etcd2 etcdctl put /test "can I write?" --command-timeout=3s
```

예상 출력:
```
Error: context deadline exceeded     ← 쓰기 불가! (과반 동의를 못 받음)
```

```bash
docker compose exec etcd2 etcdctl get /test --command-timeout=3s   # 읽기는 응답할 수 있음(설정에 따라)
```

✅ **정족수의 의미를 체감**: 1/3로는 어떤 쓰기도 합의가 안 됩니다 — K8s였다면 모든 배포/복구가 멈춘 "뇌사". 복구:

```bash
docker compose start etcd1 etcd3 2>/dev/null; docker compose start $LEADER 2>/dev/null
sleep 5; e1 endpoint status --cluster -w table
```

## Step 4. MVCC — 과거를 읽습니다

```bash
e1 put /color blue
e1 put /color red
e1 put /color green
e1 get /color -w json | python3 -c "import json,sys; d=json.load(sys.stdin); kv=d['kvs'][0]; print('value:', __import__('base64').b64decode(kv['value']).decode(), '| create_rev:', kv['create_revision'], '| mod_rev:', kv['mod_revision'], '| version:', kv['version'])"
```

예상 출력:
```
value: green | create_rev: N | mod_rev: N+2 | version: 3
```

```bash
# 과거 시점 조회!
MOD=$(e1 get /color -w json | python3 -c "import json,sys;print(json.load(sys.stdin)['kvs'][0]['mod_revision'])")
e1 get /color --rev=$((MOD-1)) | tail -1     # → red
e1 get /color --rev=$((MOD-2)) | tail -1     # → blue
```

✅ 덮어쓴 게 아니라 **버전이 쌓인 것** — K8s resourceVersion/watch 재생의 토대.

## Step 5. watch를 etcd 레벨에서

터미널 2:
```bash
cd ~/etcd-lab && docker compose exec etcd1 etcdctl watch /color
```

터미널 1:
```bash
e1 put /color purple
e1 del /color
```

터미널 2 예상:
```
PUT
/color
purple
DELETE
/color
```

✅ K8s API의 watch(모듈 21 lab)가 이 원시 기능의 포장임을 확인. `--rev=N`으로 과거부터 재생도 해보세요.

## 정리

클러스터는 lab-02에서 계속 사용.
