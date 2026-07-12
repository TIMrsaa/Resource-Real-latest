# 자가 점검 퀴즈

**Q1.** Raft의 세 요소를 설명하고, "최신 로그를 가진 노드만 리더가 될 수 있다"는 규칙이 왜 필요한가?

**Q2.** 3·4·5 노드의 쿼럼과 견디는 손실을 계산하세요. 짝수가 무의미한 이유는?

**Q3.** 커밋 지연은 무엇의 함수인가요? 이것이 "전용 SSD" 권고로 이어지는 논리를 설명하세요.

**Q4.** MVCC 리비전과 K8s의 resourceVersion의 관계는? "required revision has been compacted"가 K8s에서 무엇을 유발하나요?

**Q5.** 컴팩션과 디프래그의 차이는? `space exceeded` 복구 3단계는?

**Q6.** etcd 관측 6종 지표와, `has_leader == 0`이 뜻하는 것은?

**Q7.** 복구가 "기존 클러스터로 되돌리기"가 아닌 이유와, 프로덕션 복구 절차의 핵심 주의점 셋은?

**Q8.** K8s가 만드는 etcd 부하 다섯 가지와 각각의 완화책은?

---

## 정답

**A1.** ① 리더 선출: 하트비트가 끊기면 Candidate가 되어 투표를 요청하고 과반 득표로 리더가 됩니다(term 단조 증가). ② 로그 복제: 리더만 쓰기를 받아 로그에 append+WAL fsync하고, 과반이 fsync 완료를 응답하면 커밋해 상태 머신에 적용합니다. ③ 안전성: 후보의 로그가 투표자보다 최신이 아니면 투표하지 않습니다. 세 번째 규칙이 필요한 이유: 이미 커밋된(과반이 가진) 항목을 갖지 않은 노드가 리더가 되면 그 항목이 덮여 **커밋된 데이터가 손실**되기 때문입니다.

**A2.** 3노드: 쿼럼 2, 1대 손실 견딤. 4노드: 쿼럼 3, **1대 손실만** 견딤. 5노드: 쿼럼 3, 2대 손실 견딤. 짝수가 무의미한 이유: 4노드는 3노드와 동일한 내결함성(1대)을 가지면서 합의 시 더 많은 응답을 기다려야 하고(지연 증가) 비용도 늡니다. 그래서 3(표준) 또는 5(고가용)가 규칙이며, 7 이상은 합의 지연 때문에 드뭅니다.

**A3.** 커밋 지연 = max(리더의 WAL fsync 시간, 과반을 이루는 Follower 중 가장 느린 노드의 fsync + 네트워크 RTT). 즉 **디스크의 fsync 성능이 커밋 지연을 직접 결정**합니다. 느린 디스크 → 커밋 지연 → API 서버 쓰기 지연 → 컨트롤러 타임아웃·재시도 → 부하 증폭 → 하트비트 지연 → 리더 교체 → 선거 중 쓰기 불가 → 악화. 그래서 etcd는 전용 SSD를 쓰고 다른 I/O 워크로드와 디스크를 공유하지 않습니다.

**A4.** etcd는 MVCC로 키의 여러 버전을 리비전과 함께 보관하며, 전역 revision은 단조 증가합니다. K8s의 `resourceVersion`이 바로 이 revision이고, 낙관적 동시성(변경 충돌 감지)과 watch의 시작점으로 쓰입니다. "required revision has been compacted": informer가 오래 끊겼다 재연결하며 이미 컴팩션된 revision부터 watch하려 하면 발생 — K8s는 이때 **relist**(전체 목록 재조회)를 수행하고, 대규모 클러스터에서 이것이 API 서버·etcd에 부하 폭풍을 일으킵니다(컨트롤러 일괄 재시작이 위험한 이유).

**A5.** 컴팩션: 옛 리비전을 **논리적으로** 삭제해 keyspace 사용량(dbSizeInUse)을 줄입니다 — 파일 크기(dbSize)는 그대로. 디프래그: bbolt 파일의 빈 공간을 회수해 **실제 파일 크기**를 줄입니다 — 수행 중 그 노드가 블록되므로 멤버 하나씩 순차로. `space exceeded` 복구 3단계: ① `etcdctl compact <rev>` ② `etcdctl defrag` ③ `etcdctl alarm disarm`(알람 해제 후 쓰기 복구).

**A6.** `etcd_disk_wal_fsync_duration_seconds`(p99 < 25ms — 1번 지표), `etcd_disk_backend_commit_duration_seconds`(p99 < 25ms), `etcd_server_has_leader`, `etcd_server_leader_changes_seen_total`(증가 = 불안정), `etcd_mvcc_db_total_size_in_bytes`(quota 대비), `etcd_network_peer_round_trip_time_seconds`. `has_leader == 0`은 그 멤버가 리더를 인식하지 못한다는 뜻 — 쿼럼 상실 또는 선거 중이며, 쓰기가 불가능합니다(즉시 페이지 대상).

**A7.** 스냅샷 복구는 **새 데이터 디렉터리로 새 클러스터를 시작**하는 것이며, 복구된 클러스터는 새 cluster ID를 갖습니다 — 기존 멤버와 섞으면 안 됩니다. 주의점: ① 모든 멤버를 중지한 뒤 각 멤버에서 `--initial-cluster`·`--initial-advertise-peer-urls`를 정확히 지정해 일괄 복구합니다. ② 스냅샷 시점 이후 변경은 소실됩니다(RPO) — 복구 후 API에 없는데 kubelet이 실행 중인 Pod 등의 정리가 필요합니다. ③ 인증서·토큰의 유효 기간을 확인합니다(오래된 백업은 만료된 인증서를 담고 있을 수 있습니다). 그리고 무엇보다 **리허설된 절차**여야 합니다.

**A8.** ① watch 팬아웃(컨트롤러·API 서버의 대량 watch) → informer 공유, watch cache 튜닝, relist 폭풍 방지. ② 큰 오브젝트(큰 ConfigMap/Secret) → 1MB 제한 준수, 큰 데이터는 오브젝트 스토리지로. ③ Event 리소스의 keyspace 소모 → `--etcd-servers-overrides=/events#...`로 별도 etcd 분리. ④ 잦은 status 갱신(오퍼레이터가 초당 쓰기) → 조건 변경 시에만 갱신하도록 컨트롤러 수정. ⑤ CRD 폭증(CiliumEndpoint 등 수만 개) → 필요성·TTL 검토(16의 ArgoCD 메모리 문제와 같은 뿌리). 진단은 `/registry` 키 공간의 종류별 카운트부터.
