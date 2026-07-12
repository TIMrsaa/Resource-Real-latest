# Lab 02 — compaction, defrag, 쿼터 초과 장애, 백업/복원

> lab-01의 3노드 클러스터에서 계속. `cd ~/etcd-lab; alias e1='docker compose exec etcd1 etcdctl'`

## Step 1. 쿼터 초과 장애 재현 (안전한 환경에서 미리 겪어두기)

작은 쿼터(32MB)로 etcd1만 재구성하는 대신, 별도 1노드로 실험:

```bash
docker run -d --name tiny-etcd gcr.io/etcd-development/etcd:v3.6.0 \
  etcd --quota-backend-bytes=$((32*1024*1024)) \
  --listen-client-urls http://0.0.0.0:2379 --advertise-client-urls http://localhost:2379
alias te='docker exec tiny-etcd etcdctl'

# 1MB 값을 반복해 32MB를 채웁니다
docker exec tiny-etcd sh -c 'head -c 1048576 /dev/urandom | base64 > /tmp/big'
for i in $(seq 1 40); do
  docker exec tiny-etcd sh -c "etcdctl put /junk-$i \"\$(cat /tmp/big)\"" >/dev/null 2>&1 || { echo "FULL at $i"; break; }
done
te put /canary test
```

예상 출력:
```
FULL at 2X
Error: etcdserver: mvcc: database space exceeded     ← 쓰기 전면 거부!
```

```bash
te alarm list
```

예상: `memberID:... alarm:NOSPACE` — **알람이 서 있는 동안은 공간을 비워도 쓰기 불가.**

## Step 2. 복구 절차 (외울 가치 있는 runbook)

```bash
# ① 최신 rev 확인 후 그 시점으로 compact (옛 버전 폐기)
REV=$(te endpoint status -w json | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['Status']['header']['revision'])")
te compact $REV

# ② 필요 없는 키 삭제 + ③ defrag (물리 공간 회수)
te del /junk --prefix
te defrag

# ④ 알람 해제 (이걸 빼먹으면 영원히 읽기 전용!)
te alarm disarm

# 검증
te put /canary "writes work again" && te get /canary
```

예상: 쓰기 복구. ✅ **compact → (del) → defrag → alarm disarm** — 이 4단계가 NOSPACE 장애의 표준 복구입니다. K8s 환경이라면 원인(대형 객체 남발, Event 폭증, compaction 미작동)도 함께 잡아야 재발하지 않습니다.

```bash
docker rm -f tiny-etcd
```

## Step 3. K8s 객체가 저장된 모습 (참고: kind에서)

기여자 트랙에서 kind를 쓸 때 직접 해볼 한 줄 (지금은 읽기만):

```bash
# kind 클러스터의 etcd Pod에서:
# etcdctl get /registry/pods/default/my-pod --prefix | head
# → protobuf 바이너리 (k8s:enc:... 접두사가 보이면 암호화 설정된 것)
# 디코딩 도구: https://github.com/jpbetz/auger
```

## Step 4. 스냅샷 백업과 복원

```bash
# 백업 (lab-01에서 만든 /color 등이 들어 있습니다)
e1 put /important "production data"
docker compose exec etcd1 sh -c 'etcdctl snapshot save /tmp/backup.db && etcdutl snapshot status /tmp/backup.db -w table'
```

예상 출력:
```
+----------+----------+------------+------------+
|   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE |
+----------+----------+------------+------------+
```

```bash
# "사고" — 데이터 전부 삭제
e1 del "" --prefix --from-key 2>/dev/null || e1 del / --prefix
e1 get /important    # → (없음)

# 복원: 스냅샷 → 새 데이터 디렉터리 → 그 디렉터리로 1노드 기동
docker compose exec etcd1 sh -c '
  etcdutl snapshot restore /tmp/backup.db --data-dir /tmp/restored --name etcd1 \
    --initial-cluster etcd1=http://etcd1:2380 --initial-advertise-peer-urls http://etcd1:2380'
docker compose exec etcd1 sh -c 'nohup etcd --name etcd1 --data-dir /tmp/restored \
  --listen-client-urls http://0.0.0.0:3379 --advertise-client-urls http://localhost:3379 \
  --listen-peer-urls http://0.0.0.0:3380 --initial-advertise-peer-urls http://etcd1:3380 >/tmp/r.log 2>&1 &'
sleep 3
docker compose exec etcd1 etcdctl --endpoints=http://localhost:3379 get /important
```

예상 출력:
```
/important
production data        ← 부활!
```

✅ 복원 = **백업 시점으로의 전체 되감기** (그 후의 모든 변경 소실). K8s에서 이 수술이 얼마나 큰일인지(전 클러스터 상태 되감기!) 체감했다면, 리소스 단위 백업 도구(Velero — 모듈 36)가 별도로 존재하는 이유도 명확해집니다.

## 정리

```bash
cd ~/etcd-lab && docker compose down -v
docker rm -f tiny-etcd 2>/dev/null || true
cd ~ && rm -rf ~/etcd-lab
```
