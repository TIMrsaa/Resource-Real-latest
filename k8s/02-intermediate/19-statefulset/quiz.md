# 자가 점검 퀴즈

**Q1.** Deployment로 3중 복제 DB를 못 돌리는 이유 3가지는?

**Q2.** db-1 Pod가 재생성될 때 보존되는 것 2가지와 바뀌는 것 1가지는?

**Q3.** volumeClaimTemplates가 만드는 PVC의 이름 규칙과, StatefulSet 삭제 시 그 PVC의 운명은?

**Q4.** `serviceName`이 가리켜야 하는 Service의 종류와 그 이유는?

**Q5.** replicas=5, partition=3이면 이미지 업데이트 시 어떤 Pod들이 새 버전이 되는가요?

**Q6.** 노드 장애로 Terminating에 갇힌 db-0을 StatefulSet이 재생성하지 않는 이유와 안전한 해소 절차는?

**Q7.** 3중 etcd류 클러스터(정족수 2)에 필요한 PDB 설정은?

---

## 정답

**A1.** ① 멤버별 개별 디스크 불가(PVC 공유는 RWO 충돌/동시 쓰기 불가) ② 임의 Pod 이름이라 고정 신원(primary 지명, 멤버 명단) 불가 ③ 동시 기동이라 순서(primary 먼저) 보장 불가.

**A2.** 보존: **이름(db-1)** 과 **PVC(data-db-1, 데이터 포함)**. 바뀜: **Pod IP** (그래서 통신은 멤버 DNS 이름으로).

**A3.** `<템플릿이름>-<statefulset>-<순번>` (예: data-db-1). StatefulSet을 지워도 **PVC는 기본적으로 남습니다** (데이터 보호 — retentionPolicy로 변경 가능).

**A4.** **Headless Service** (`clusterIP: None`). 멤버 직통 DNS(`db-0.db...`)를 만들려면 가상 IP 분배가 아니라 Pod별 A 레코드가 필요하기 때문.

**A5.** 순번 ≥ partition, 즉 **db-3, db-4**만 (큰 번호부터 순차로). db-0~2는 옛 버전 유지 — 카나리 검증 후 partition을 내려 확산.

**A6.** 같은 신원이 두 개 살아 있을 가능성(split-brain) 때문에 K8s가 보수적으로 대기합니다. 절차: 인스턴스의 물리적 종료 확인 → `kubectl delete node <노드>` (kubelet 부재 확정 → 자동 재생성) → 그래도 안 되면 최후수단으로 force delete.

**A7.** `minAvailable: 2` — 자발적 중단(drain 등)이 동시에 1개까지만 빠지게 하여 정족수 붕괴 방지.
