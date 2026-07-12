# Lab 02 — 스냅샷·복구, 그리고 디스크가 클러스터를 정하는 것을 봅니다

k8s 36의 백업을 원리로 되짚고, `wal_fsync_duration`이 왜 1번 지표인지 확인합니다.

전제: lab-01의 kind 클러스터(etcd), etcd-lab 컨테이너.

## Step 1. 스냅샷 백업 — 온라인으로

```bash
E() { docker exec etcd-control-plane etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key "$@"; }

# 백업 전에 표식이 될 리소스 생성
kubectl create ns before-backup >/dev/null
kubectl create cm marker -n before-backup --from-literal=state=saved >/dev/null

docker exec etcd-control-plane sh -c '
  ETCDCTL_API=3 etcdctl \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    snapshot save /tmp/backup.db'

docker exec etcd-control-plane sh -c '
  etcdutl snapshot status /tmp/backup.db --write-out=table 2>/dev/null || \
  ETCDCTL_API=3 etcdctl snapshot status /tmp/backup.db --write-out=table'
```

✅ 스냅샷의 메타데이터: revision, 키 수, 해시. **이 시점 이후의 변경은 복구 시 소실**됩니다(RPO — k8s 36).

## Step 2. 백업 이후의 변경 — RPO를 눈으로

```bash
kubectl create ns after-backup >/dev/null
kubectl create cm lost -n after-backup --from-literal=state=will-be-lost >/dev/null
kubectl get ns | grep -E "before-backup|after-backup"
echo "→ after-backup은 스냅샷에 없습니다. 복구하면 사라집니다."
```

## Step 3. 복구 — 새 클러스터 ID가 생깁니다

```bash
cat <<'EOF'
★ 복구는 "기존 클러스터에 되돌리기"가 아니라 "새 데이터 디렉터리로 새 클러스터 시작"입니다

프로덕션 절차 (3노드 기준):
  1. 모든 etcd 멤버 중지 (static Pod면 매니페스트를 임시 이동)
  2. 각 멤버에서:
     etcdutl snapshot restore backup.db \
       --name m1 \
       --initial-cluster m1=https://10.0.1.1:2380,m2=https://10.0.1.2:2380,m3=https://10.0.1.3:2380 \
       --initial-cluster-token new-token \
       --initial-advertise-peer-urls https://10.0.1.1:2380 \
       --data-dir /var/lib/etcd-new
  3. etcd 데이터 디렉터리 교체 → etcd 시작 (새 cluster ID)
  4. kube-apiserver 재시작 → 컨트롤러들이 재수렴
  5. 검증: 노드 Ready, 워크로드 상태, 인증서 유효성

주의:
  - 복구된 클러스터의 cluster ID가 다르므로 옛 멤버와 섞으면 안 됩니다
  - 스냅샷 시점 이후 생성된 리소스는 사라집니다 (Pod는 kubelet이 알지만 API에는 없음 → 정리 필요)
  - 인증서·토큰의 유효 기간 확인 (오래된 백업 복구 시 만료 가능)
EOF
```

실습(kind 단일 노드에서 안전하게 개념 확인):

```bash
docker exec etcd-control-plane sh -c '
  etcdutl snapshot restore /tmp/backup.db --data-dir /tmp/etcd-restored --name etcd-control-plane \
    --initial-cluster etcd-control-plane=https://127.0.0.1:2380 \
    --initial-advertise-peer-urls https://127.0.0.1:2380 2>&1 | tail -3
  echo "---"
  ls /tmp/etcd-restored/member/'
echo "→ 복구된 데이터 디렉터리가 생성됐습니다 (실제 교체는 etcd 중지 후)"
```

## Step 4. 디스크 지연 — 1번 지표

```bash
kubectl -n kube-system port-forward pod/etcd-etcd-control-plane 2381:2381 >/dev/null 2>&1 &
sleep 3
curl -sk http://localhost:2381/metrics 2>/dev/null | grep -E "^etcd_disk_wal_fsync_duration_seconds_bucket" | tail -4 || \
  docker exec etcd-control-plane sh -c 'curl -sk https://127.0.0.1:2379/metrics \
    --cacert /etc/kubernetes/pki/etcd/ca.crt --cert /etc/kubernetes/pki/etcd/server.crt \
    --key /etc/kubernetes/pki/etcd/server.key 2>/dev/null | grep -E "wal_fsync_duration_seconds_(sum|count)"'
kill %1 2>/dev/null || true
```

```bash
cat <<'EOF'
=== etcd 관측의 6종 (theory §4) ===
etcd_disk_wal_fsync_duration_seconds       ★ p99 < 25ms  (디스크!)
etcd_disk_backend_commit_duration_seconds  ★ p99 < 25ms
etcd_server_has_leader                     ★ 0이면 쿼럼 상실 — 즉시 페이지
etcd_server_leader_changes_seen_total      증가 = 불안정 (디스크·네트워크)
etcd_mvcc_db_total_size_in_bytes           quota 대비 (space exceeded 예방)
etcd_network_peer_round_trip_time_seconds  피어 지연

PromQL (11):
  histogram_quantile(0.99, sum by(le)(rate(etcd_disk_wal_fsync_duration_seconds_bucket[5m])))
  → 0.025 초과 시 경보

번짐의 경로:
  fsync 지연 → 커밋 지연 → API 서버 쓰기 지연 → 컨트롤러 타임아웃
  → 재시도 폭풍 → 하트비트 지연 → 리더 교체 → 선거 중 쓰기 불가 → 악화
★ 그래서 etcd는 전용 SSD. 다른 워크로드와 디스크 공유 금지
EOF
```

## Step 5. K8s가 만드는 부하 — 무엇을 줄일까

```bash
E get /registry --prefix --keys-only 2>/dev/null | grep -v '^$' | \
  awk -F/ '{print $3}' | sort | uniq -c | sort -rn | head -8

cat <<'EOF'

부하 완화 처방 (theory §5):
① Event 분리:
   kube-apiserver --etcd-servers-overrides=/events#https://etcd-events:2379
   → 이벤트 전용 etcd로 (keyspace·부하 격리)
② 큰 오브젝트 금지:
   ConfigMap/Secret 1MB 제한 — 큰 데이터는 오브젝트 스토리지로
③ 잦은 status 갱신 줄이기:
   오퍼레이터가 초당 status를 쓰면 리비전 폭증 → 조건 변경 시에만 갱신
④ CRD 폭증 관리:
   CiliumEndpoint 같은 대량 CRD → 정말 필요한가, TTL은?
⑤ watch 최적화:
   API 서버의 watch cache, 컨트롤러의 informer 공유 (relist 폭풍 방지)
EOF
```

## Step 6. 백업 자동화와 리허설 (k8s 36의 완성)

```bash
cat <<'EOF'
# CronJob 백업 (개념)
apiVersion: batch/v1
kind: CronJob
metadata: { name: etcd-backup, namespace: kube-system }
spec:
  schedule: "0 */6 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          hostNetwork: true
          nodeSelector: { node-role.kubernetes.io/control-plane: "" }
          tolerations: [{ operator: Exists }]
          containers:
            - name: backup
              image: registry.k8s.io/etcd:3.5.16-0
              command:
                - sh
                - -c
                - |
                  etcdctl snapshot save /backup/etcd-$(date +%F-%H%M).db \
                    --endpoints=https://127.0.0.1:2379 \
                    --cacert=/pki/ca.crt --cert=/pki/server.crt --key=/pki/server.key
                  etcdutl snapshot status /backup/etcd-*.db --write-out=table | tail -3
                  # 오프사이트로 업로드 (S3 등) + 보존 정책
              volumeMounts:
                - { name: pki, mountPath: /pki, readOnly: true }
                - { name: backup, mountPath: /backup }
          volumes:
            - { name: pki, hostPath: { path: /etc/kubernetes/pki/etcd } }
            - { name: backup, hostPath: { path: /var/backups/etcd } }
          restartPolicy: OnFailure

★ 그리고 분기마다 복구 리허설 (Game Day — k8s 36)
  "리허설하지 않은 백업은 백업이 아니다"
  체크: 스냅샷 status 검증, 실제 복구 시간(RTO), 복구 후 워크로드 정상성
EOF
```

## Step 7. 산출물 — etcd 운영 카드

```markdown
# etcd 운영 체크리스트
## 배치
- [ ] 홀수 노드(3 또는 5), 전용 SSD, 다른 워크로드와 디스크 공유 금지
- [ ] heartbeat-interval / election-timeout을 네트워크 RTT에 맞게

## 관측 (알람)
- [ ] wal_fsync p99 > 25ms  → 디스크 문제
- [ ] has_leader == 0        → 쿼럼 상실, 즉시 페이지
- [ ] leader_changes 증가    → 불안정
- [ ] db_total_size vs quota → space exceeded 예방

## 유지보수
- [ ] 자동 컴팩션(kube-apiserver --etcd-compaction-interval=5m)
- [ ] 주기적 defrag (멤버 하나씩! 동시 실행 = 쿼럼 상실)
- [ ] Event 분리(--etcd-servers-overrides), 큰 오브젝트 금지

## 백업·복구
- [ ] 정기 스냅샷 + 오프사이트 + status 검증
- [ ] 복구는 새 cluster ID를 만듭니다 — 모든 멤버 중지 후 일괄 복구
- [ ] 분기 복구 리허설 (RTO/RPO 실측)
```

## 정리

```bash
bash cleanup.sh
```
