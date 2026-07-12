# Lab 02 — 멀티아치 3종 비교와 Dockerfile 너머 (ko·buildpacks)

eks 19에서 소비자로 만난 멀티아치 이미지를 생산자로 만듭니다 — 세 방법의 시간을 직접 잽니다.

전제: lab-01의 빌더(lab)와 저장소(~/ci-lab/buildkit).

## Step 1. QEMU 에뮬레이션 — 되긴 되는데 느립니다

```bash
cd ~/ci-lab/buildkit

# binfmt 등록 (커널이 arm64 바이너리를 만나면 QEMU로 번역하게)
docker run --privileged --rm tonistiigi/binfmt --install arm64 >/dev/null
docker buildx inspect lab --bootstrap | grep Platforms   # linux/arm64 추가 확인

cat > app.go <<'EOF'
package main
import "fmt"
func main() { fmt.Println("hello multiarch") }
EOF
cat > go.mod <<'EOF'
module app
go 1.23
EOF

# 나쁜 예: 빌드 자체를 arm64로 에뮬레이션
cat > Dockerfile.emu <<'EOF'
# syntax=docker/dockerfile:1.7
FROM golang:1.23 AS build
COPY . /src
RUN cd /src && go build -o /app .
FROM gcr.io/distroless/static
COPY --from=build /app /app
ENTRYPOINT ["/app"]
EOF
time docker buildx build -f Dockerfile.emu --platform linux/arm64 -t lab:emu . 2>&1 | tail -1
```

예상: go build(컴파일)가 QEMU 위에서 돌아 **수 분** 걸릴 수 있습니다. ✅ 명령어 단위 번역의 대가(theory §5) — "arm64 빌드만 40분"의 원인.

## Step 2. 크로스 컴파일 — $BUILDPLATFORM의 마법

```bash
cat > Dockerfile <<'EOF'
# syntax=docker/dockerfile:1.7
FROM --platform=$BUILDPLATFORM golang:1.23 AS build    # ★ 빌드는 러너 아치에서
ARG TARGETOS TARGETARCH
COPY . /src
RUN cd /src && GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /app .
FROM gcr.io/distroless/static                           # 최종만 타깃 아치
COPY --from=build /app /app
ENTRYPOINT ["/app"]
EOF
time docker buildx build --platform linux/arm64,linux/amd64 -t lab:cross . 2>&1 | tail -1
```

예상: 두 아치 합쳐도 Step 1의 단일 arm64보다 빠릅니다 — 컴파일이 전부 네이티브(amd64)에서 돌고 산출물만 교차. ✅ `--platform=$BUILDPLATFORM` + `TARGETARCH` 패턴(theory §5). Go/Rust처럼 크로스 컴파일이 좋은 언어의 특권.

## Step 3. manifest list 해부 — 소비자가 자동으로 받는 원리

```bash
TAG=ttl.sh/multiarch-$(uuidgen | cut -c1-8):1h
docker buildx build --platform linux/arm64,linux/amd64 --push -t $TAG . >/dev/null 2>&1

docker buildx imagetools inspect $TAG
```

예상 출력 구조:

```
Name:      ttl.sh/multiarch-xxxx:1h
MediaType: application/vnd.oci.image.index.v1+json     ← manifest list!
Manifests:
  Name:     ...@sha256:aaa...   Platform: linux/arm64
  Name:     ...@sha256:bbb...   Platform: linux/amd64
```

✅ 태그 하나가 **index → 아치별 manifest**를 가리킵니다. eks 19의 Graviton 노드는 이 index에서 arm64를 골라 pull했던 것. `exec format error`는 이 목록에 노드 아치가 없을 때입니다. 다이제스트 고정(04)은 **index의 digest**로 — 그래야 두 아치 모두 커버.

## Step 4. 네이티브 arm64 러너 — GHA에서 세 방법 비교

```bash
cat > .github/workflows/multiarch.yml <<'EOF'
name: multiarch-compare
on: [push, workflow_dispatch]
permissions: { contents: read }
jobs:
  emulated:
    runs-on: ubuntu-latest            # amd64 러너에서 QEMU
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-qemu-action@v3
      - uses: docker/setup-buildx-action@v3
      - run: |
          START=$(date +%s)
          docker buildx build -f Dockerfile.emu --platform linux/arm64 -t emu .
          echo "QEMU 에뮬레이션: $(( $(date +%s) - START ))초"
  cross:
    runs-on: ubuntu-latest            # amd64 러너에서 크로스 컴파일
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - run: |
          START=$(date +%s)
          docker buildx build --platform linux/arm64 -t cross .
          echo "크로스 컴파일: $(( $(date +%s) - START ))초"
  native:
    runs-on: ubuntu-24.04-arm         # ★ 네이티브 arm64 러너 (퍼블릭 저장소 무료)
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - run: |
          START=$(date +%s)
          docker buildx build -f Dockerfile.emu --platform linux/arm64 -t native .
          echo "네이티브 arm64: $(( $(date +%s) - START ))초"
EOF
git add -A && git commit -qm "lab: multiarch three ways" && git push -q
sleep 120
gh run view --log 2>/dev/null | grep -E "에뮬레이션:|크로스 컴파일:|네이티브" | head -5
```

예상: 네이티브 ≈ 크로스 << 에뮬레이션. ✅ 세 방법의 트레이드오프를 숫자로(theory §5). 사내라면 08의 ARC를 Graviton 노드그룹(eks 17의 Karpenter로)에 얹는 것이 네이티브 경로입니다.

## Step 5. ko — Go라면 Dockerfile도 데몬도 없습니다

```bash
go install github.com/google/ko@latest 2>/dev/null || brew install ko 2>/dev/null || true
export KO_DOCKER_REPO=ttl.sh/ko-$(uuidgen | cut -c1-8)

# Dockerfile 없음. 소스 → 멀티아치 이미지 + push까지 한 줄:
ko build --platform=linux/amd64,linux/arm64 --bare . 2>&1 | tail -2
```

예상: 이미지 참조(digest 포함)가 출력 — Dockerfile 없이, 도커 데몬 없이, 멀티아치로 push됐습니다. ✅ ko는 Go 빌드 캐시를 그대로 쓰고 base(distroless)에 바이너리만 얹습니다 — Tekton(16)이 이것으로 빌드되는 이유이자, 재현성 높은 빌드(21)의 모범.

## Step 6. buildpacks — 감지·표준화·rebase

```bash
(curl -sSL https://github.com/buildpacks/pack/releases/latest/download/pack-linux.tgz \
  | tar -xz -C /usr/local/bin 2>/dev/null) || brew install buildpacks/tap/pack 2>/dev/null || true

pack build lab-cnb --builder paketobuildpacks/builder-jammy-tiny --path . 2>&1 | tail -5
docker run --rm lab-cnb 2>/dev/null || true
```

예상: pack이 Go 프로젝트를 **감지**해 Dockerfile 없이 빌드. ✅ CNB의 자리: 수백 팀에 "Dockerfile 금지, 표준 빌더만"을 강제하는 조직 — 그리고 **rebase**(`pack rebase`)로 앱 레이어 재빌드 없이 베이스 OS만 교체(전사 일괄 패치가 초 단위).

## Step 7. 산출물 — 도구 선택 결정표

```markdown
# 빌드 도구 선택 (모두 OCI 이미지를 만듭니다)
- Dockerfile 이미 있음 + 범용        → BuildKit (buildx) — 기본값
- Go 서비스                          → ko (데몬·Dockerfile 없음, 재현성)
- 수백 팀 표준화 + 베이스 일괄 패치   → buildpacks (rebase)
- K8s 러너에서 특권 없이              → BuildKit rootless / 원격 buildkitd
  (kaniko는 2025 아카이브 — 신규 채택 금지, 기존 것은 이전 계획)
- arm64 생산                         → 크로스 컴파일 우선, 안 되면 네이티브 러너, QEMU는 최후
```

## 정리

```bash
bash cleanup.sh
```
