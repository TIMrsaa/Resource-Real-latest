# Lab 01 — pull 병목의 이해와 P2P 구조

P2P는 규모가 본질이라 kind에서 완전 재현은 어렵습니다. 이 랩은 병목을 계산으로 이해하고, Dragonfly 구조를 설치로 확인합니다.

전제: kind, kubectl, helm.

## Step 1. 병목을 숫자로 — star 토폴로지의 한계

```bash
cat <<'EOF'
=== 대규모 pull 병목 계산 (theory §1) ===
star 토폴로지: 모든 노드가 레지스트리에서 pull

레지스트리 전송량 = 노드 수 × 이미지 크기

시나리오:
  일반 앱 (200MB 이미지):
    100 노드   → 20 GB    (여유)
    1,000 노드 → 200 GB   (레지스트리 대역에 따라 느려짐)
  
  AI 이미지 (8GB 이미지):
    100 노드   → 800 GB   (이미 부담)
    1,000 노드 → 8 TB     (레지스트리 무너짐)
    5,000 노드 (대규모 학습) → 40 TB 동시 → 불가능

동시성 문제:
  배포·오토스케일 시 노드들이 '동시에' pull
  → 순차면 견디지만 동시면 대역·연결 포화
  → pull이 초 → 분 → 타임아웃 (18의 콜드스타트 악화)
EOF
```

## Step 2. 병목이 나타나는 실무 상황

```bash
cat <<'EOF'
=== P2P가 필요해지는 순간 (theory §1) ===
① 대규모 롤아웃:
   1,000 노드에 새 버전 배포 → 1,000 동시 pull
   → 배포가 몇 분씩 (01의 피드백 루프 붕괴)

② 오토스케일 폭발:
   Karpenter(eks 17)가 트래픽 급증에 수백 노드 생성
   → 수백 노드가 동시에 이미지 pull
   → 스케일이 이미지 pull에 막혀 느려짐 (18)

③ AI 분산 학습:
   Volcano(02)가 수천 노드에 학습 잡 스케줄
   → 수천 노드가 수 GB 이미지 동시 pull
   → 레지스트리가 학습 시작의 병목

④ 엣지·다중 지역:
   레지스트리에서 먼 노드들 → 지연·대역 제약

→ 이 상황들의 공통점: 노드 수 × 이미지 크기 × 동시성
EOF
```

## Step 3. Dragonfly 설치 — 구조 확인

```bash
kind create cluster --name dragonfly -q

helm repo add dragonfly https://dragonflyoss.github.io/helm-charts >/dev/null 2>&1
helm install dragonfly dragonfly/dragonfly -n dragonfly-system --create-namespace >/dev/null 2>&1 || \
  echo "(설치에 시간 — kubectl -n dragonfly-system get pods 로 확인)"
sleep 30
kubectl -n dragonfly-system get pods 2>/dev/null | head -8
```

## Step 4. 컴포넌트 지도

```bash
echo "=== Dragonfly 컴포넌트 (theory §2) ==="
kubectl -n dragonfly-system get deploy,daemonset,statefulset 2>/dev/null | grep -i drag | head -8

cat <<'EOF'
역할:
  Manager     클러스터 관리·설정·모니터링
  Scheduler   피어 조율 (누가 누구에게서 조각을 받을지)
  Seed Peer   레지스트리에서 먼저 받아 시드 (back-to-source)
  Peer(dfdaemon, DaemonSet): 각 노드의 데몬 — 조각 받고·제공
EOF
```

## Step 5. P2P 배포 원리 — BitTorrent

```bash
cat <<'EOF'
=== P2P 원리 (theory §2) ===
전통(star):
  노드1 ← 레지스트리
  노드2 ← 레지스트리
  ...
  노드1000 ← 레지스트리     (레지스트리가 1000번 전송)

P2P(mesh):
  노드1,2,3 ← Seed Peer ← 레지스트리   (레지스트리 몇 번만)
  노드4 ← 노드1의 조각A + 노드2의 조각B  (P2P!)
  노드5 ← 노드3,4의 조각
  ...
  → 받은 노드가 다음 노드의 소스가 됨
  → swarm이 클수록 조각 소스도 많아 빠릅니다

조각(piece):
  이미지를 조각으로 나눠 → 한 명이 다 가질 때까지 안 기다림
  여러 소스에서 조각을 병렬로 → 조립
  (BitTorrent가 파일을 배포하는 방식)

핵심:
  레지스트리 전송량 ≈ 일정 (노드 수와 무관)
  → 스케일의 벽을 넘습니다
EOF
```

## Step 6. 통합 — containerd registry mirror (26)

```bash
cat <<'EOF'
=== pull 경로 통합 (theory §3, 26) ===
containerd(26)의 config.toml에서 레지스트리 미러를 dfdaemon으로:

[plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
  endpoint = ["http://127.0.0.1:65001"]   # dfdaemon

→ containerd가 이미지 pull 시 dfdaemon으로 요청
→ dfdaemon이 P2P로 조각을 모아 containerd에 전달
→ 앱·K8s는 아무것도 안 바뀜 (투명)

즉:
  26에서 본 containerd의 pull 경로
  (콘텐츠 저장소 ← 레지스트리)
  가
  (콘텐츠 저장소 ← dfdaemon ← P2P mesh)
  로 바뀝니다 (투명하게)
EOF
```

## Step 7. 산출물

```markdown
# Dragonfly P2P 카드
- 문제: 대규모 이미지 배포의 병목 (레지스트리 전송량 = 노드×크기×동시성)
- 본질: star 토폴로지의 선형 부하 (성능 아닌 구조)
- P2P: 노드끼리 조각 공유 → 노드 늘수록 소스도 늘어 부하 일정(BitTorrent)
- 컴포넌트: Manager·Scheduler·Seed Peer·Peer(dfdaemon)
- 통합: containerd registry mirror (26의 pull 경로에 투명하게)
- 필요 상황: 대규모 롤아웃·오토스케일 폭발·AI 학습·엣지
```

## 정리

lab-02에서 지연 로딩·AI·판단을 다룹니다. 유지.
