# 이론 — Raft, MVCC 저장, 컴팩션/디프래그, 성능의 물리학, 백업·복구

> **🌱 17세 눈높이 비유: 학급 회의록**
> - **Raft** = 회의록 작성 규칙. **서기(리더) 한 명**만 기록하고, **과반이 확인 서명**하면 확정
> - **쿼럼** = 과반 — 5명 학급이면 3명. 4명이면? 여전히 3명 필요(1명 결석만 견딤) → **짝수는 손해**
> - **리더 선출** = 서기가 안 보이면(하트비트 없음) 아무나 손을 듭니다. 단 **최신 회의록을 가진 사람**만 서기가 될 수 있습니다
> - **WAL(fsync)** = 회의록을 볼펜으로 눌러 쓰기 — 지우개로 못 지웁니다(내구성). 근데 **볼펜이 느리면 회의가 느려집니다**
> - **MVCC 리비전** = 회의록에 줄을 긋지 않고 새 줄로 추가 — 옛 내용도 남아 있습니다(과거 조회 가능)
> - **컴팩션** = 오래된 줄을 "무효" 표시 (공책 두께는 그대로)
> - **디프래그** = 공책을 새로 옮겨 적어 실제로 얇게 만들기 — **그동안 회의는 멈춥니다**

---

## 1. Raft — 세 요소

### 리더 선출

```
상태: Follower → (선거 타임아웃) → Candidate → (과반 득표) → Leader
term(임기): 단조 증가. 더 높은 term을 보면 즉시 Follower로

안전성 규칙: 후보의 로그가 투표자의 로그보다 최신이 아니면 투표하지 않습니다
  → 커밋된 항목을 가진 노드만 리더가 될 수 있습니다 (데이터 손실 방지)
```

### 로그 복제와 커밋

```
클라이언트 쓰기 → 리더가 로그에 append + WAL fsync
  → Follower들에게 AppendEntries
  → 과반이 fsync 완료를 응답하면 → 커밋 → 상태 머신(MVCC)에 적용 → 클라이언트에 응답
★ 커밋 지연 = max(리더 fsync, 과반 중 가장 느린 Follower의 fsync + 네트워크)
```

### 쿼럼과 노드 수

| 노드 | 쿼럼 | 견디는 손실 | 평가 |
|---|---|---|---|
| 1 | 1 | 0 | 개발용 |
| 3 | 2 | **1** | 표준 |
| 4 | 3 | 1 | ❌ 3과 같은데 느립니다 |
| 5 | 3 | **2** | 대규모·고가용 |
| 7 | 4 | 3 | 합의 지연 증가 — 드묾 |

**학습자(learner) 노드**: 투표하지 않고 로그만 받는 멤버 — 신규 멤버를 안전하게 합류시키거나 읽기 전용 복제에 씁니다.

### 읽기의 종류

```
선형화 읽기(기본): 리더에게 물어보고, 리더가 "내가 아직 리더인가"를 과반에 확인(ReadIndex)
  → K8s가 기대하는 "최신 상태" 보장
직렬화 읽기(--consistency=s): 로컬 노드에서 즉시 응답 — 낡을 수 있습니다(빠름)
```

## 2. MVCC 저장 모델

```
key → [ (rev1, value1), (rev2, value2), ... ]      다중 버전
전역 revision(단조 증가) — K8s의 resourceVersion이 이것

  Put(a, "x")  → rev 5
  Put(a, "y")  → rev 6      (rev 5의 값은 아직 존재!)
  Get(a, --rev=5) → "x"     (과거 조회)

watch: "rev N 이후의 변경을 스트리밍" ← 컨트롤러가 이것으로 폴링 없이 반응(09 lab)
  ★ 필요한 rev가 컴팩션됐으면? → "required revision has been compacted" 에러
    → K8s의 informer가 relist(전체 목록 재조회)를 하게 됨 (API 서버 부하 급증)
```

### 저장 계층

```
WAL(write-ahead log): 순차 쓰기, fsync — 내구성. 크래시 복구
snapshot:             주기적으로 상태를 통째로 저장 → WAL 잘라내기
boltdb(bbolt) 파일:   B+tree — 실제 키-값 저장 (default.etcd/member/snap/db)
```

## 3. 컴팩션과 디프래그 — 다른 청소

| | 컴팩션(compact) | 디프래그(defrag) |
|---|---|---|
| 대상 | 옛 리비전(논리) | 파일의 빈 공간(물리) |
| 효과 | keyspace 사용량↓ | **DB 파일 크기↓** |
| 영향 | 가벼움 | **그 노드가 블록** (순차 수행 필수!) |
| 자동 | K8s API 서버가 5분마다 자동 컴팩션 | 수동/운영 스크립트 |

```
etcd --auto-compaction-mode=periodic --auto-compaction-retention=1h  (etcd 자체 옵션)
kube-apiserver --etcd-compaction-interval=5m                          (K8s 기본, 이것이 작동 중)

★ 컴팩션을 해도 db 파일은 안 줄어듭니다 → 계속 쓰면 quota(기본 2GiB)에 도달
   → "mvcc: database space exceeded" → etcd가 읽기 전용 → K8s 전체 쓰기 불가 ⚠️
   복구: ① compact ② defrag ③ alarm disarm
```

## 4. 성능의 물리학 — 디스크가 클러스터를 정합니다

```
etcd_disk_wal_fsync_duration_seconds     ★ 1번 지표 (p99 < 25ms)
etcd_disk_backend_commit_duration_seconds  (p99 < 25ms)
etcd_server_leader_changes_seen_total     (증가 = 불안정)
etcd_server_has_leader                    (0 = 쿼럼 상실!)
etcd_mvcc_db_total_size_in_bytes          (quota 대비)
etcd_network_peer_round_trip_time_seconds (피어 지연)

번짐의 경로:
  느린 디스크 → fsync 지연 → 커밋 지연 → API 서버 쓰기 지연
  → 컨트롤러 타임아웃·재시도 → 부하 증폭 → 하트비트 지연 → 리더 교체
  → 선거 중 쓰기 불가 → 더 큰 재시도 폭풍
★ 그래서 etcd는 전용 SSD, 다른 워크로드와 디스크 공유 금지
   heartbeat-interval / election-timeout 을 네트워크 RTT에 맞게 (기본 100ms / 1000ms)
```

## 5. K8s가 만드는 etcd 부하

```
① watch: 컨트롤러·API 서버가 대량의 watch 유지 → 이벤트 팬아웃
② 큰 오브젝트: 큰 ConfigMap/Secret(1MB 제한), 거대한 CRD 상태
③ Event 리소스: 기본 TTL 1시간, 대량 생성 → keyspace 소모 (별도 etcd로 분리 가능!)
④ 잦은 상태 업데이트: 오퍼레이터가 status를 초당 갱신하면 리비전 폭증
⑤ CRD 폭증: CiliumEndpoint 같은 것이 수만 개 (16의 ArgoCD 메모리 문제와 같은 뿌리)

진단: etcdctl로 키 공간 분석
  etcdctl get /registry --prefix --keys-only | awk -F/ '{print $3}' | sort | uniq -c | sort -rn
```

## 6. 백업과 복구 (k8s 36의 원리)

```bash
# 백업 — 온라인 스냅샷 (리더/팔로워 아무 노드에서나)
etcdctl snapshot save backup.db --endpoints=... --cacert=... --cert=... --key=...
etcdctl snapshot status backup.db --write-out=table   # revision, 키 수, 해시

# 복구 — 새 데이터 디렉터리를 만듭니다 (기존 클러스터에 합류하는 것이 아닙니다!)
etcdutl snapshot restore backup.db \
  --name m1 --initial-cluster m1=https://... --initial-advertise-peer-urls https://... \
  --data-dir /var/lib/etcd-restored
# → 모든 멤버를 중지 → 각 멤버를 복구된 데이터로 시작 (새 클러스터 ID)
```

```
복구의 진실 (k8s 36):
  - 스냅샷은 그 시점의 상태 → 이후 변경은 소실 (RPO)
  - 복구된 클러스터는 새 cluster ID → 옛 멤버와 섞이면 안 됩니다
  - K8s 복구: etcd 복구 + 정적 Pod 재시작 + 인증서 유효성 + 컨트롤러 재수렴
  - ★ 리허설하지 않은 백업은 백업이 아닙니다 (Game Day)
```

## 7. 소스/도구에서 확인하기

- etcd: https://etcd.io/docs — op-guide(하드웨어, 튜닝, 재해 복구), learning(API, Raft)
- Raft 논문·시각화: https://raft.github.io
- K8s의 etcd 운영: https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/
- 09·k8s 36 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| Raft 세 요소? | 리더 선출(최신 로그만 리더) / 로그 복제(과반 fsync) / 안전성 |
| 왜 홀수? | 4노드는 쿼럼 3 — 3노드와 같은 내결함성에 지연만 증가 |
| 커밋 지연? | max(리더 fsync, 과반 중 최악 fsync + RTT) |
| MVCC? | 리비전별 다중 버전 — K8s의 resourceVersion, watch의 근거 |
| 컴팩션 vs 디프래그? | 옛 리비전 논리 삭제 vs 파일 물리 축소(그동안 블록) |
| space exceeded? | 컴팩션만으론 파일 안 줆 → quota 도달 → 읽기 전용. compact→defrag→alarm disarm |
| 1번 지표? | `etcd_disk_wal_fsync_duration_seconds` p99 < 25ms — 전용 SSD |
| 복구의 진실? | 새 cluster ID, RPO 존재, 리허설 없는 백업은 백업이 아닙니다 |
