# Lab 02 — 이미지 저장, 스냅샷터, 그리고 확장 플랫폼

콘텐츠 저장소와 스냅샷터로 이미지가 어떻게 관리되는지 열어보고, containerd가 확장 플랫폼인 이유를 확인합니다.

전제: lab-01의 클러스터(kind: ctrd).

## Step 1. 콘텐츠 저장소 — 다이제스트로 관리되는 blob

```bash
N() { docker exec ctrd-control-plane "$@"; }

# 이미지 하나 pull
N crictl pull alpine:3.19 >/dev/null 2>&1
sleep 3

echo "=== 콘텐츠 저장소의 blob (다이제스트 = 콘텐츠 주소) ==="
N ctr -n k8s.io content list 2>/dev/null | head -6
echo ""
echo "=== 실제 파일 위치 ==="
N ls /var/lib/containerd/io.containerd.content.v1.content/blobs/sha256/ 2>/dev/null | head -4
echo "→ 파일명이 곧 다이제스트 (cicd 04·19의 콘텐츠 주소)"
```

✅ **같은 다이제스트 = 같은 내용 = 한 번만 저장**(레이어 공유). 이미지가 레이어를 공유하면 디스크를 아낍니다.

## Step 2. 스냅샷터 — 레이어가 파일시스템이 되는 곳

```bash
echo "=== 스냅샷 목록 (overlayfs 레이어) ==="
N ctr -n k8s.io snapshots list 2>/dev/null | head -8

echo ""
echo "=== 스냅샷터가 쓰는 디스크 ==="
N du -sh /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs 2>/dev/null

cat <<'EOF'
스냅샷 체인 (theory §3):
  이미지 레이어들 → 스냅샷터가 overlayfs로 쌓습니다
  lowerdir(읽기전용 하위 레이어들) + upperdir(컨테이너 쓰기 레이어) = merged
  → 컨테이너가 보는 파일시스템

★ 디스크 사용의 대부분이 여기 → "노드 디스크 참" 진단의 출발점
EOF
```

## Step 3. 디스크 압박 진단 — 실무 시나리오

```bash
echo "=== 이미지가 디스크를 얼마나 쓰나 ==="
N crictl images 2>/dev/null | head -8
echo ""
echo "=== 미사용 이미지 GC (kubelet이 자동으로 하지만 수동도 가능) ==="
cat <<'EOF'
디스크 참(disk pressure) 진단·대응:
  1. 콘텐츠 저장소 + 스냅샷터 크기 확인 (위)
  2. 미사용 이미지: crictl images로 확인, kubelet의 imageGC가 자동
     (--image-gc-high-threshold=85 / low=80 — 85% 넘으면 GC)
  3. 수동 정리: crictl rmi --prune (미사용 이미지)
  4. 큰 이미지가 범인이면: 멀티스테이지(cicd 04), 작은 베이스(distroless)
  ★ 노드의 DiskPressure taint → Pod eviction → 이 층을 봐야 합니다
EOF
```

## Step 4. OCI 스펙 — 03의 config.json 재확인

```bash
echo "=== 실행 중 컨테이너의 OCI 스펙 (03의 config.json) ==="
CID=$(N crictl ps -q 2>/dev/null | head -1)
N crictl inspect $CID 2>/dev/null | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    info = d.get('info',{})
    spec = info.get('runtimeSpec',{})
    print('namespaces:', [n['type'] for n in spec.get('linux',{}).get('namespaces',[])][:5])
    print('runtime:', info.get('runtimeType','?'))
except Exception as e: print('(crictl inspect로 직접 확인)')
" 2>/dev/null || echo "  N crictl inspect $CID 로 확인"
echo "→ 03에서 본 OCI runtime-spec — containerd가 shim에 넘기는 그 스펙"
```

## Step 5. RuntimeClass — 03의 격리 스펙트럼과 연결

```bash
echo "=== containerd 설정의 런타임 핸들러 (03 lab에서 본 것) ==="
N cat /etc/containerd/config.toml 2>/dev/null | grep -A3 "runtimes.runc" | head -6

cat <<'EOF'
RuntimeClass → containerd 런타임 핸들러 (03·theory §4):
  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]  ← 기본
  [plugins."...runtimes.runsc]   ← gVisor (설치 시)
  [plugins."...runtimes.kata]    ← Kata (설치 시)
  [plugins."...runtimes.wasm]    ← runwasi (Wasm)

각 핸들러가 다른 shim을 지정 → RuntimeClass가 그 핸들러를 고릅니다
→ "Pod마다 다른 격리"(03)의 실현 지점
EOF
```

## Step 6. 확장 플랫폼 — runwasi, nerdctl, 지연 로딩

```bash
cat <<'EOF'
=== containerd가 확장 플랫폼인 이유 (guide) ===

① runwasi (Wasm 워크로드):
   containerd-shim-wasm 설치 → RuntimeClass handler=wasm
   → Wasm 모듈을 컨테이너처럼 K8s에서 실행 (03의 Wasm 노선 합류)
   → ms 콜드스타트·수 MB 이미지 (18의 콜드스타트 문제의 다른 답)

② 대체 스냅샷터 (지연 로딩):
   stargz-snapshotter / SOCI(AWS) / nydus
   → 이미지 전체를 안 받고 필요한 부분만 lazy pull
   → 큰 ML 이미지의 콜드스타트 대폭 단축 (18과 연결)
   containerd 설정에서 스냅샷터 교체

③ nerdctl (Docker 호환 CLI):
   docker build/run/compose를 containerd로 (Docker 데몬 없이)
   rootless 지원 → 03의 rootless 빌드(cicd 19의 kaniko 대체)

④ BuildKit 백엔드:
   cicd 19의 BuildKit이 containerd를 백엔드로 사용 가능

→ 03에서 "containerd = 범용"이라 한 것의 실체:
  K8s 밖에서도, 다양한 워크로드 타입으로도 확장됩니다
EOF
```

## Step 7. 진단 도구 체인 완성 (20과 연결)

```bash
cat <<'EOF'
# 노드 수준 진단 도구 체인 (20에서 예고 → 여기서 완성)
kubectl        K8s API (워크로드 뷰)
  ↓ 안 보이면
crictl         CRI 레벨 (kubelet과 같은 뷰, 자동 k8s.io)
  crictl ps / pods / images / logs / inspect / stats
  ↓ 더 깊이
ctr -n k8s.io  containerd 네이티브 (콘텐츠·스냅샷·task)
  ctr -n k8s.io containers/snapshots/content/images list
  ↓ 커널
ps / /sys/fs/cgroup / nsenter  (03의 프로세스·네임스페이스·cgroup)

★ 층마다 도구가 있습니다 (03의 체인 = 진단 체인)
EOF
```

## Step 8. 산출물

```markdown
# containerd 이미지·확장 카드
- 콘텐츠 저장소: 다이제스트 blob (콘텐츠 주소, 레이어 공유)
- 스냅샷터: overlayfs 레이어 → 컨테이너 파일시스템 (디스크의 대부분!)
- 디스크 진단: content + snapshots 크기 → 미사용 이미지 GC (imageGC threshold)
- RuntimeClass: containerd 런타임 핸들러 → 다른 shim (gVisor/Kata/Wasm)
- 확장: runwasi(Wasm), stargz/SOCI(지연로딩), nerdctl(Docker UX), BuildKit
- 진단 체인: kubectl → crictl → ctr -n k8s.io → ps/cgroup
```

## 정리

```bash
bash cleanup.sh
```
