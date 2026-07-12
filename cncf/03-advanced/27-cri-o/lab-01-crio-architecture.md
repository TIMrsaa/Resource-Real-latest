# Lab 01 — CRI-O 구조와 containers/ 생태계

CRI-O를 직접 설치하기는 무겁고 환경 의존적이므로, 이 랩은 개념 확인 + containers/ 생태계 도구(Podman/Skopeo) 체험 중심입니다.

전제: docker (Podman/Skopeo는 컨테이너로 실행), 인터넷.

## Step 1. containers/ 생태계를 컨테이너로 체험

```bash
mkdir -p ~/cncf-lab/crio && cd ~/cncf-lab/crio

# Skopeo: 이미지 검사 (CRI-O가 쓰는 containers/image 라이브러리 기반)
docker run --rm quay.io/skopeo/stable inspect docker://docker.io/library/alpine:3.19 2>/dev/null | \
  python3 -c "
import json,sys
d = json.load(sys.stdin)
print('이미지:', d.get('Name'))
print('레이어 수:', len(d.get('Layers',[])))
print('아키텍처:', d.get('Architecture'))
print('→ Skopeo는 CRI-O와 같은 containers/image 라이브러리를 쓴다')
" 2>/dev/null || echo "(네트워크/이미지 pull에 따라)"
```

✅ **Skopeo가 이미지를 검사**하는 것 = CRI-O가 이미지를 pull할 때 쓰는 같은 라이브러리(theory §3).

## Step 2. 서명 검증 정책 — 21과의 접점

```bash
cat <<'EOF'
=== containers/image의 서명 검증 정책 (theory §5, 21) ===

/etc/containers/policy.json:
{
  "default": [{"type": "reject"}],           # 기본: 모두 거부
  "transports": {
    "docker": {
      "quay.io/myorg": [
        {"type": "sigstoreSigned", "keyPath": "/etc/pki/cosign.pub"}  # cosign 서명 검증
      ],
      "docker.io/library": [{"type": "insecureAcceptAnything"}]        # 공식 이미지 허용
    }
  }
}

→ CRI-O(그리고 Podman)가 이미지를 pull할 때 이 정책으로 서명 검증
→ 21에서 admission(Kyverno)으로 한 검증을 런타임 레벨에서도 (다층 방어)
→ OpenShift는 이 정책을 클러스터 이미지 정책으로 통합
EOF
```

## Step 3. CRI-O 아키텍처 — 구성 요소 지도

```bash
cat <<'EOF'
=== CRI-O가 kubelet의 요청을 처리하는 구조 (theory §1) ===

kubelet ──CRI gRPC──▶ crio 데몬
                        │
                        ├─ CRI 구현 (RunPodSandbox/CreateContainer/StartContainer)
                        │    26의 containerd CRI 플러그인과 같은 CRI 명세
                        │
                        ├─ containers/storage (이미지·컨테이너 저장)
                        │    /var/lib/containers/storage/
                        │
                        ├─ containers/image (pull·서명 검증)
                        │
                        ├─ conmon (컨테이너당 모니터 — 26의 shim 역할)
                        │    stdio·종료 수호 + CRI-O 재시작에도 컨테이너 생존
                        │
                        └─ crun (기본 OCI 런타임) → 실제 컨테이너

26(containerd)과의 구조 대비:
  containerd = 자체 콘텐츠 저장소 + 스냅샷터 + shim v2 (전부 자체)
  CRI-O      = containers/ 공유 라이브러리 + conmon (조립)
  → "덜 만들고 더 조립한다"
EOF
```

## Step 4. crun — 경량 런타임 확인

```bash
# crun을 컨테이너에서 버전 확인 (또는 개념)
cat <<'EOF'
=== crun vs runc (theory §4) ===
crun: C 작성 → 바이너리 작음, 시작 빠름, 메모리 적음
runc: Go 작성 → 기준 구현, 생태계 넓음

CRI-O의 기본이 crun인 이유:
  K8s 전용이라 "가장 효율적인 기본값"을 고를 자유
  고밀도 노드에서 컨테이너당 오버헤드가 누적되므로 경량이 유리

단 격리 스펙트럼(03)은 런타임과 무관:
  crun/runc(공유 커널) → runsc/gVisor(유저스페이스 커널) → kata(microVM)
  CRI-O도 RuntimeClass로 이들을 고를 수 있습니다
EOF
```

## Step 5. kind로 실제 CRI 흐름 재확인 (containerd지만 CRI는 같습니다)

```bash
# CRI 명세 자체는 containerd·CRI-O가 동일 → kind(containerd)로 CRI 개념 확인
kind create cluster --name crio-concept -q 2>/dev/null || echo "(이미 있으면 재사용)"
kubectl run demo --image=alpine --command -- sleep 3600 2>/dev/null
sleep 5

echo "=== crictl은 containerd·CRI-O 모두에서 같은 명령 (CRI 레벨) ==="
docker exec crio-concept-control-plane crictl ps 2>/dev/null | head -3
docker exec crio-concept-control-plane crictl pods 2>/dev/null | head -3

cat <<'EOF'
→ crictl은 CRI 레벨 도구라 containerd든 CRI-O든 같은 명령
  (26에서 배운 crictl이 CRI-O에서도 그대로)
  차이는 그 아래(containerd의 ctr vs CRI-O의 crio-status·containers/ 도구)
EOF
```

## Step 6. 버저닝 정책 확인

```bash
cat <<'EOF'
=== K8s 정렬 버저닝 (theory §2) ===
CRI-O 릴리스: 1.28, 1.29, 1.30, 1.31...
Kubernetes:   1.28, 1.29, 1.30, 1.31...
→ 같은 마이너 버전이 함께 릴리스·지원

실무 의미:
  K8s 1.30 클러스터 → CRI-O 1.30
  K8s 업그레이드 1.30→1.31 → CRI-O도 1.30→1.31
  "이 CRI-O가 이 K8s와 맞나요?"를 확인할 필요 없음

containerd(26)는 독립 버저닝:
  containerd 1.7.x가 K8s 1.28~1.31을 지원 (호환성 매트릭스 확인)
  → 유연하지만 확인이 필요
EOF
```

## Step 7. 산출물

```markdown
# CRI-O 구조 카드
- CRI 구현 + containers/storage·image(공유) + conmon(shim역할) + crun(기본)
- "덜 만들고 더 조립" (containerd는 전부 자체 구현)
- K8s 정렬 버저닝 (1.30↔1.30) — 호환성 확인 불필요, 유연성 없음
- containers/ 생태계 형제: Podman(실행)·Buildah(빌드)·Skopeo(검사)
- 서명 검증: containers/image의 policy.json (21의 런타임 레벨)
- crictl은 CRI 레벨이라 containerd·CRI-O 공통
```

## 정리

lab-02에서 containerd와 직접 대비합니다. kind 클러스터 유지.
