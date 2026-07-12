# Lab 01 — Ceph 구조와 Rook의 자동화

Ceph는 무거워 kind에서 완전 재현이 어렵습니다. 이 랩은 Ceph 구조를 이해하고 Rook 오퍼레이터의 CR 모델을 확인합니다.

전제: kind, kubectl (개념 + Rook Operator 구조).

## Step 1. "Rook은 스토리지가 아니다" 재확인 (05)

```bash
cat <<'EOF'
=== 05의 통과 의례 심층 (theory §1) ===
Rook = 오퍼레이터 (데이터 저장 안 함)
Ceph = 스토리지 시스템 (실제 데이터, 성능·내구성)

"Rook을 쓴다" = "Ceph를 운영한다 + 그 운영을 Rook에 위임"

평가 대상 둘:
  Ceph: 아키텍처·성능·내구성 (시스템)
  Rook: 자동화 품질·업그레이드 안전 (오케스트레이터)

→ Rook을 이해하려면 먼저 Ceph를 이해해야 (그것이 자동화 대상)
EOF
```

## Step 2. Ceph 컴포넌트

```bash
cat <<'EOF'
=== Ceph 아키텍처 (theory §1) ===
OSD (Object Storage Daemon):
  디스크 하나당 하나 → 실제 데이터 저장·복제·복구
  수백~수천 개 (규모)
MON (Monitor):
  클러스터 맵(OSD 상태) 관리, 쿼럼 합의 (21) — 홀수(3/5)
MGR (Manager):
  통계·모니터링·대시보드
MDS (Metadata Server):
  CephFS(파일)의 메타데이터

RADOS (기반):
  신뢰성 있는 분산 오브젝트 저장
  → 그 위에 RBD(블록)·CephFS(파일)·RGW(오브젝트)

★ MON 쿼럼:
  21의 합의(홀수·쿼럼)가 Ceph의 클러스터 맵 관리에
  MON 과반이 살아야 클러스터 동작 (etcd·TiKV와 같은 계보)
EOF
```

## Step 3. CRUSH — 중앙 조회 없는 배치

```bash
cat <<'EOF'
=== CRUSH (theory §2) ===
문제: 수천 OSD 중 데이터가 어디에?
전통: 중앙 메타데이터 서버 (병목·SPOF)
CRUSH: 알고리즘으로 계산 (조회 없이!)
  CRUSH(오브젝트ID, 클러스터맵) → OSD 목록
  → 클라이언트가 직접 계산 (중앙 조회 불필요)

장애 도메인:
  CRUSH 맵 계층(호스트·랙·DC) → 복제본을 다른 도메인에
  → 04의 안티어피니티, 21의 복제 사고

37 TiKV와 대비:
  TiKV: PD가 Region 위치를 조회 (중앙 메타데이터)
  Ceph: CRUSH로 계산 (조회 없음)
  → 위치 결정의 두 접근 (조회 vs 계산)
EOF
```

## Step 4. Rook Operator 설치 (구조 확인)

```bash
kind create cluster --name rook -q

kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/crds.yaml 2>/dev/null
kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/common.yaml 2>/dev/null
kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/operator.yaml 2>/dev/null || \
  echo "(Operator 설치 — 실제 Ceph 클러스터는 디스크·리소스 필요, 구조 이해 중심)"
sleep 20
kubectl -n rook-ceph get pods 2>/dev/null | head -5
kubectl get crd | grep ceph | head -6
```

## Step 5. CR 모델 — K8s 선언으로 Ceph 운영

```bash
cat <<'EOF'
=== Rook CR 모델 (theory §3, 08) ===
CephCluster: 클러스터 정의
  apiVersion: ceph.rook.io/v1
  kind: CephCluster
  spec:
    cephVersion: { image: quay.io/ceph/ceph:v18 }
    mon: { count: 3 }              # MON 쿼럼 (21)
    storage:
      useAllNodes: true
      useAllDevices: true          # 노드의 디스크를 OSD로
    → Rook이 이 선언대로 OSD·MON·MGR 배포

CephBlockPool: 블록 스토리지 풀 (RBD)
CephFilesystem: 파일 (CephFS)
CephObjectStore: 오브젝트 (S3 호환 RGW)

→ kubectl로 스토리지 시스템을 운영 (08의 오퍼레이터)
  "K8s 선언 → Rook이 Ceph 운영으로 번역"
EOF
```

## Step 6. Rook이 자동화하는 것

```bash
cat <<'EOF'
=== Rook 자동화 (theory §3) ===
① 설치: CephCluster CR → OSD·MON·MGR 배포
② OSD 관리: 디스크 추가 → OSD 생성, 실패 → 교체
③ MON 쿼럼: MON 유지, 실패 시 재생성 (21)
④ 재분배: 노드 추가/제거 → 데이터 rebalance
⑤ 업그레이드: Ceph 버전 업 (데이터 실은 채)
⑥ 헬스: Ceph 상태 → CR status

→ 전에는 Ceph 전문 엔지니어가 수동으로 하던 것을 코드로

★ but Rook이 없애지 못하는 것:
  Ceph 성능 튜닝 (풀·PG 수·CRUSH 규칙)
  심각한 장애 복구 (여러 OSD 동시 실패, 데이터 손상)
  → "설치는 쉽지만 운영은 여전히 Ceph" (05의 사고)
EOF
```

## Step 7. 산출물

```markdown
# Rook-Ceph 구조 카드
## Ceph (시스템)
- OSD(디스크·데이터)·MON(맵·쿼럼 21)·MGR·MDS
- RADOS 기반 → RBD(블록)·CephFS(파일)·RGW(오브젝트)
- CRUSH: 중앙 조회 없이 위치 계산 (확장성)

## Rook (오퍼레이터)
- CephCluster/BlockPool/Filesystem/ObjectStore CR
- 자동화: 설치·OSD·MON쿼럼·재분배·업그레이드·헬스
- kubectl로 스토리지 시스템 운영 (08)

## 한계
- Ceph 성능 튜닝·심각한 복구는 여전히 어렵습니다
- "설치의 쉬움 ≠ 운영의 쉬움" (05의 사고)
```

## 정리

lab-02에서 Capability Level과 판단을 다룹니다. 유지.
