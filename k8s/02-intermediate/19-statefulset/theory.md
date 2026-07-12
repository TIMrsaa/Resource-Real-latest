# 이론 — StatefulSet의 3대 보장과 운영 동작

> **🌱 17세 눈높이 비유: 기숙사 "지정 호실"**
> Deployment의 Pod는 **찜질방 손님**입니다 — 아무 자리나 눕고, 나가면 그 자리는 아무 의미 없습니다.
> StatefulSet의 Pod는 **기숙사 사생**입니다 — 101호(db-0), 102호(db-1) 호실이 정해져 있고, 각 호실에 **개인 사물함(PVC)** 이 있습니다. 사생이 잠시 나갔다 와도(재시작) 같은 호실, 같은 사물함입니다. 입사도 호실 순서대로(101 먼저), 퇴사는 역순(끝방부터).

---

## 1. 3대 보장

### ① 안정적 신원 (Stable Identity)

```
Pod 이름: <statefulset>-0, -1, -2...     (순번, 영속)
DNS:     db-0.db.shop.svc.cluster.local  (Headless Service 경유 멤버 직통)
```

- Headless Service(모듈 16)가 **필수 짝꿍** (`spec.serviceName`으로 지정) — ClusterIP 분배가 아니라 멤버 지명이 필요하니까
- 앱 설정에 "primary는 db-0, replicas는 db-1,db-2"처럼 **이름을 박을 수 있게 됩니다**

### ② 멤버별 스토리지 (volumeClaimTemplates)

```yaml
spec:
  volumeClaimTemplates:        # PVC의 "틀" — 멤버마다 하나씩 찍어냄
  - metadata: { name: data }
    spec:
      accessModes: [ReadWriteOnce]
      storageClassName: gp3
      resources: { requests: { storage: 1Gi } }
```

- 생성되는 PVC: `data-db-0`, `data-db-1`... — **Pod와 1:1 영속 결합**
- db-1이 재생성되면 (다른 노드라도) `data-db-1`이 다시 붙습니다 — RWO여도 문제없음(멤버당 1개니까)
- **StatefulSet을 삭제해도 PVC는 남습니다** — 데이터 보호 기본값. (1.27+ `persistentVolumeClaimRetentionPolicy`로 자동 삭제 선택 가능)

### ③ 순서 보장 (Ordered)

```
생성: 0 → (Ready 확인) → 1 → (Ready) → 2        # 순차
삭제/스케일인: 2 → 1 → 0                          # 역순
업데이트: 큰 번호부터 하나씩
```

- `podManagementPolicy: Parallel`로 순서가 불필요한 워크로드(캐시 등)는 병렬 기동 가능
- 순차 기동이 클러스터형 DB의 "primary 먼저, 조인은 나중에" 요구와 맞물립니다

## 2. 업데이트 전략

```yaml
updateStrategy:
  type: RollingUpdate          # 큰 번호부터 하나씩 (기본)
  rollingUpdate:
    partition: 2               # ★ 순번 ≥ 2 만 업데이트 — 카나리!
```

- **partition 카나리**: partition=2면 db-2만 새 버전 → 검증 후 partition을 1, 0으로 내리며 확산. Deployment의 카나리(모듈 06 가중치)와 다른, 상태 워크로드 특유의 점진 배포
- `OnDelete`: 자동 업데이트 안 함 — 운영자가 Pod를 지울 때만 (가장 보수적)

## 3. Deployment와의 비교 총정리

| | Deployment | StatefulSet |
|---|---|---|
| Pod 이름 | 무작위 해시 | 순번 (영속) |
| 스토리지 | (공유하면 충돌) | 멤버별 PVC 자동 |
| DNS | Service 분배만 | 멤버 직통 (Headless) |
| 기동/종료 | 동시 | 순차/역순 |
| 스케일 속도 | 빠름 | 순차라 느림 |
| 삭제 시 | 깨끗이 소멸 | **PVC 잔존** (보호) |
| 용도 | 무상태 앱 (대부분) | DB, 브로커, 합의 시스템 |

## 4. 주의가 필요한 동작 2가지

### 강제 삭제 = split-brain 위험

노드 통신 두절 시 StatefulSet은 Deployment와 달리 **대체 Pod를 바로 안 만듭니다** — 같은 신원(db-0)이 두 개 존재하면 데이터가 갈라지기(split-brain) 때문. `--force --grace-period=0`은 "그 노드에서 진짜 죽었음을 내가 보증한다"는 선언입니다 — 보증 못 하면 쓰지 마세요 (모듈 10 pitfall의 근거).

### PodDisruptionBudget과 한 세트

DB 3중 클러스터에서 노드 정리(drain)가 동시에 2개를 빼가면 정족수(quorum) 붕괴. `PDB: minAvailable: 2`로 "동시에 1개까지만 빼라"를 선언 — 모듈 35(업그레이드)에서 본격 사용.

## 5. 소스코드에서 확인하기

- StatefulSet 컨트롤러: `pkg/controller/statefulset/stateful_set_control.go` — 순번 계산과 "하나 Ready 후 다음" 로직
- PVC 생성부: 같은 파일의 `getPersistentVolumeClaims` — volumeClaimTemplates → 멤버별 PVC 네이밍

## 요약 카드

| 질문 | 답 |
|------|----|
| 3대 보장? | 고정 신원(이름/DNS), 멤버별 PVC, 순차 기동/역순 종료 |
| 필수 짝꿍? | Headless Service (serviceName) |
| db-1 재생성 시 디스크는? | `data-db-1` PVC가 그대로 재부착 |
| StatefulSet 삭제 시 데이터? | PVC 잔존 (기본) — 의도적 보호 |
| 카나리 방법? | updateStrategy partition |
| 강제 삭제의 위험? | 같은 신원 중복 → split-brain |
