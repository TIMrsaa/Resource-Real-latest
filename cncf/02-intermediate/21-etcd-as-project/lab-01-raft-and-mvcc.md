# Lab 01 — 합의를 관찰하고, MVCC를 파고, space exceeded를 만들어 고칩니다

etcd의 내부를 etcdctl로 직접 열어봅니다 — 그리고 유명한 장애를 재현·복구합니다.

전제: kind, kubectl, docker.

## Step 1. 클러스터와 etcdctl 준비

```bash
kind create cluster --name etcd -q

# etcd static Pod 안에서 etcdctl 사용 (kind는 단일 노드)
E() { docker exec etcd-control-plane etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key "$@"; }

E endpoint status --write-out=table
E member list --write-out=table
```

✅ 단일 멤버(kind), `IS LEADER: true`. 프로덕션은 3 또는 5(theory §1).

## Step 2. Raft 상태 관찰

```bash
echo "=== 멤버·term·리더 ==="
E endpoint status --write-out=json | python3 -c "
import json,sys
d = json.load(sys.stdin)[0]
s = d['Status']
print(f\"  version   : {s['version']}\")
print(f\"  dbSize    : {s['dbSize']:,} bytes\")
print(f\"  dbSizeInUse: {s.get('dbSizeInUse',0):,} bytes   ← 실제 사용(컴팩션 후)\")
print(f\"  leader    : {s['leader']}\")
print(f\"  raftTerm  : {s['raftTerm']}    (임기 — 리더 교체마다 증가)\")
print(f\"  raftIndex : {s['raftIndex']}   (로그 인덱스)\")
"
```

✅ `dbSize`(파일 크기)와 `dbSizeInUse`(실사용)의 차이가 **디프래그로 회수 가능한 공간**입니다(theory §3).

## Step 3. MVCC — 리비전과 과거 조회

```bash
E put /demo/key "v1" >/dev/null
REV1=$(E get /demo/key -w json | python3 -c "import json,sys; print(json.load(sys.stdin)['header']['revision'])")
E put /demo/key "v2" >/dev/null
E put /demo/key "v3" >/dev/null

echo "현재 값:";     E get /demo/key --print-value-only
echo "rev=$REV1 시점의 값:"; E get /demo/key --rev=$REV1 --print-value-only
echo ""
echo "=== K8s의 resourceVersion이 곧 이 revision ==="
kubectl create cm probe --from-literal=a=1 >/dev/null
kubectl get cm probe -o jsonpath='{.metadata.resourceVersion}'; echo
E get /registry/configmaps/default/probe -w json | python3 -c "
import json,sys
kv = json.load(sys.stdin)['kvs'][0]
print('etcd mod_revision:', kv['mod_revision'])"
```

✅ **K8s의 resourceVersion = etcd의 revision** — 낙관적 동시성(conflict 감지)과 watch의 시작점이 여기서 나옵니다(theory §2).

## Step 4. watch와 컴팩션의 충돌 — "revision compacted"

```bash
CUR=$(E endpoint status -w json | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['Status']['header']['revision'])")
echo "현재 revision: $CUR"

# 리비전을 만들고 컴팩션
for i in $(seq 1 20); do E put /demo/churn "$i" >/dev/null; done
E compact $((CUR + 10)) 2>&1 | head -1

echo ""
echo "=== 컴팩션된 리비전을 watch하려 하면? ==="
E watch --rev=$CUR /demo/churn 2>&1 | head -2 &
sleep 3; kill %1 2>/dev/null

cat <<'EOF'
→ "required revision has been compacted"

K8s에서의 의미:
  informer가 오래 끊겼다 재연결하면 그 revision이 이미 컴팩션됨
  → relist(전체 목록 재조회) → API 서버·etcd 부하 급증
  → 대규모 클러스터에서 컨트롤러 재시작이 폭풍을 일으키는 이유
EOF
```

## Step 5. 키 공간 분석 — 무엇이 etcd를 채우나

```bash
echo "=== /registry 아래 리소스 종류별 키 수 ==="
E get /registry --prefix --keys-only 2>/dev/null | grep -v '^$' | \
  awk -F/ '{print $3}' | sort | uniq -c | sort -rn | head -10

echo ""
echo "=== 총 키 수 ==="
E get "" --from-key --keys-only 2>/dev/null | grep -vc '^$' || true
```

✅ 실제 클러스터에서는 `events`, `pods`, `leases`, 그리고 CRD(CiliumEndpoint 등)가 상위를 차지합니다 — 16에서 본 ArgoCD 메모리 문제와 같은 뿌리(theory §5).

## Step 6. "database space exceeded" 재현

```bash
# quota를 아주 작게 설정한 별도 etcd를 컨테이너로 (실클러스터 etcd를 망가뜨리지 않기 위해)
docker run -d --name etcd-lab -p 12379:2379 \
  quay.io/coreos/etcd:v3.5.16 \
  /usr/local/bin/etcd \
    --name lab --data-dir /etcd-data \
    --listen-client-urls http://0.0.0.0:2379 --advertise-client-urls http://0.0.0.0:2379 \
    --quota-backend-bytes 16777216 >/dev/null   # 16MB quota

sleep 5
L() { docker exec etcd-lab etcdctl --endpoints=http://127.0.0.1:2379 "$@"; }
L endpoint status --write-out=table

echo "=== quota를 채웁니다 (같은 키를 계속 갱신 → 리비전 누적) ==="
docker exec etcd-lab sh -c '
  V=$(head -c 100000 /dev/urandom | base64 | head -c 100000)
  for i in $(seq 1 200); do
    etcdctl --endpoints=http://127.0.0.1:2379 put key-$i "$V" >/dev/null 2>&1 || break
  done' 2>/dev/null

sleep 2
echo ""
echo "=== 알람 확인 ==="
L alarm list
L put newkey value 2>&1 | head -1
```

예상: `etcdserver: mvcc: database space exceeded` — **쓰기가 전면 차단**됩니다. 실제 K8s라면 이 순간 클러스터가 읽기 전용이 됩니다(theory §3).

## Step 7. 복구 3단계 — compact → defrag → alarm disarm

```bash
echo "=== 1. 현재 revision 확인 ==="
REV=$(L endpoint status -w json | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['Status']['header']['revision'])")
echo "revision: $REV"

echo "=== 2. 컴팩션 (옛 리비전 논리 삭제) ==="
L compact $REV 2>&1 | head -1
L endpoint status --write-out=table | head -4
echo "→ dbSizeInUse는 줄었지만 dbSize(파일)는 그대로!"

echo "=== 3. 디프래그 (파일 물리 축소 — 이 동안 블록됨) ==="
L defrag 2>&1 | head -1
L endpoint status --write-out=table | head -4
echo "→ 이제 dbSize도 줄었다"

echo "=== 4. 알람 해제 ==="
L alarm disarm
L alarm list
L put newkey value 2>&1 | head -1
echo "→ 쓰기 복구 ✅"
```

✅ **컴팩션만으로는 파일이 안 줄어듭니다** — 이것이 "compact 했는데 여전히 space exceeded"의 정체입니다(theory §3).

```bash
cat <<'EOF'
프로덕션 예방:
  - kube-apiserver의 --etcd-compaction-interval=5m (기본, 자동 컴팩션)
  - 주기적 defrag (멤버 하나씩! 동시에 하면 쿼럼 상실)
      etcdctl defrag --cluster  ← 순차 수행하지만 운영 중에는 신중히
  - quota-backend-bytes 상향 (기본 2GiB, 최대 8GiB 권장)
  - alarm 모니터링: etcd_server_quota_backend_bytes vs mvcc_db_total_size_in_bytes
  - Event를 별도 etcd로 분리 (--etcd-servers-overrides)
EOF
```

## Step 8. 산출물

```markdown
# etcd 내부 카드
- revision = K8s의 resourceVersion (MVCC 전역 카운터)
- watch는 revision 기반 → 컴팩션된 rev를 요구하면 relist 폭풍
- dbSize(파일) vs dbSizeInUse(실사용) — 차이가 디프래그로 회수할 공간
- space exceeded 복구: compact → defrag → alarm disarm
- 키 공간 분석: /registry 아래 종류별 키 수 (events·CRD가 범인인 경우 多)
```

## 정리

lab-02에서 계속. etcd-lab 컨테이너는 유지.
