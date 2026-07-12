# 이론 — Raft, MVCC, watch, 유지보수

> **🌱 17세 눈높이 비유: 3명의 서기가 쓰는 학급 일지**
> 학급의 공식 기록(일지)을 잃어버리지 않으려고 서기 3명이 **같은 내용을 각자** 적습니다.
> - **리더 선출**: 서기 중 1명이 "기록 대표". 대표가 결석하면 남은 2명이 즉시 투표로 새 대표를 뽑습니다(수 초).
> - **정족수**: 새 내용은 **과반(2명)이 받아 적어야** 공식 기록이 됩니다. 대표 혼자 적은 건 무효 — 그래서 대표가 죽어도 기록이 안 갈립니다.
> - **revision**: 일지의 줄 번호. 절대 재사용하지 않고 증가만 합니다. "몇 번째 줄 이후의 변화"를 물을 수 있습니다(watch).
> - **compaction**: 일지가 두꺼워지면 오래된 줄의 "수정 전 내용"을 지워 줄입니다.

---

## 1. Raft — 분산 합의

### 쓰기의 여정

```
클라이언트 → 리더에게 쓰기 요청
리더: 로그에 기록 + 팔로워들에게 복제 전송
팔로워 과반이 "받았다" 응답 → 리더가 커밋 → 클라이언트에 성공 응답
```

- **모든 쓰기는 리더를 거칩니다** (팔로워에 온 쓰기는 리더로 전달). 읽기는 기본적으로도 선형화(linearizable) 보장을 위해 리더 확인을 거침
- **리더 선출**: 팔로워가 하트비트를 못 받으면(기본 1초 election timeout) 후보로 전환 → 투표 → 과반 득표 시 리더. 클러스터는 이 수 초간 **쓰기 불가** (읽기는 가능)

### 정족수 산수 (운영의 뼈대)

| 노드 수 | 정족수 | 허용 장애 |
|---------|--------|----------|
| 1 | 1 | 0 (장애=전체 다운) |
| 3 | 2 | **1** |
| 5 | 3 | **2** |
| 4 | 3 | 1 (3노드와 같습니다 — 낭비!) |

정족수를 잃으면(3노드 중 2대 사망): 클러스터는 **읽기 전용 좀비**가 됩니다 — 모듈 02의 "뇌사" 상태. EKS가 멀티 AZ에 3(+)개를 깔아주는 이유.

### 디스크가 전부입니다

Raft 로그는 매 쓰기마다 fsync됩니다 — etcd 성능 = **디스크 fsync 지연**. 권고: 전용 SSD, `wal_fsync_duration_seconds` p99 < 10ms. "etcd가 느리다" = 거의 항상 디스크 문제입니다. 네트워크 지연도 합의 왕복에 직결 — 멀티 리전 etcd가 금기인 이유.

## 2. MVCC와 revision

etcd는 덮어쓰지 않습니다 — **모든 버전을 보관**합니다(Multi-Version Concurrency Control):

```
put /color blue   → revision 5:  /color = blue
put /color red    → revision 6:  /color = red   (blue도 rev5로 여전히 조회 가능!)
del /color        → revision 7:  (삭제 표시)
```

- `etcdctl get /color --rev=5` → blue — **과거를 읽을 수 있습니다**
- K8s 객체의 resourceVersion = 그 객체가 마지막으로 수정된 etcd revision
- watch가 "rev N 이후"를 정확히 재생할 수 있는 것도 MVCC 덕

### compaction — 과거 정리

이력이 무한히 쌓이면 디스크 폭발 → 주기적으로 "rev N 이전의 옛 버전 폐기". K8s API 서버가 기본 5분마다 자동 compaction 요청. **compaction된 rev로의 watch 요청이 410 Gone**(모듈 21)의 정체.

### defrag — 빈 공간 회수

compaction은 논리 삭제라 파일 크기는 안 줄어듭니다(내부 빈 페이지로 남음). `etcdctl defrag`가 물리적 재정리 — 단 **노드별로 순차 실행**(defrag 중 그 노드는 응답 정지).

### 쿼터 — DB 크기 한도

기본 2GiB(권장 한도 ~8GiB). 초과 시 **알람 + 클러스터 전체 쓰기 거부**(`mvcc: database space exceeded`) — 읽기만 되는 좀비. 복구: compact → defrag → 알람 해제. lab-02에서 직접 재현합니다.

## 3. K8s가 etcd를 쓰는 방식

```
키:  /registry/<리소스종류>/<네임스페이스>/<이름>
     /registry/pods/default/my-pod
     /registry/secrets/prod/db-cred        ← 암호화 대상(KMS — 모듈 07)
값:  protobuf 직렬화된 객체 (사람이 직접 읽기 어려움)
```

- API 서버만 접근(모듈 02 철칙) — etcd 입장에서 K8s는 "클라이언트 하나"
- Event 리소스는 별도 etcd로 분리하는 운영 패턴이 있습니다(수다스러워서) — 대규모 튜닝(모듈 37)

## 4. 백업과 복원

```bash
etcdctl snapshot save backup.db        # 일관된 시점 스냅샷
etcdutl snapshot restore backup.db --data-dir /new/dir   # 새 데이터 디렉터리로 복원
```

- 복원은 "새 클러스터를 만드는 것"입니다 — 복원 시점 이후의 모든 변경은 소실
- EKS: AWS가 자동 백업 (우리에게는 안 보임). 그래도 **K8s 리소스 레벨 백업(Velero — 모듈 36)** 이 별도로 필요한 이유: etcd 복원은 "전체 되감기"라 특정 네임스페이스만 복구 같은 수술이 불가능

## 5. 소스코드에서 확인하기

- etcd: https://github.com/etcd-io/etcd — `server/etcdserver/raft.go`(Raft 연동), `server/storage/mvcc/`(MVCC 본체)
- Raft 라이브러리(분리됨): https://github.com/etcd-io/raft — 논문 구현체로 유명, 주석이 교과서입니다
- K8s 쪽 etcd 클라이언트: `staging/src/k8s.io/apiserver/pkg/storage/etcd3/store.go`

## 요약 카드

| 질문 | 답 |
|------|----|
| 쓰기 성공의 조건? | 리더 경유 + 과반 복제 (정족수) |
| 3노드가 표준인 이유? | 1대 장애 허용 + 합의 비용 최소 (4노드는 낭비) |
| resourceVersion의 정체? | etcd revision (MVCC 카운터) |
| 410 Gone의 etcd 측 원인? | 요청 rev가 compaction으로 폐기됨 |
| "쓰기 전부 거부" 장애? | DB 쿼터 초과 — compact+defrag로 복구 |
| etcd 성능의 지배 변수? | 디스크 fsync 지연 |
