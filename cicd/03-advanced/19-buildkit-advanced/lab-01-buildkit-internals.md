# Lab 01 — BuildKit 내부 관찰: 병렬 DAG, 캐시 판정, 익스포트

빌드 로그를 "결과"가 아니라 "솔버의 판정 기록"으로 읽는 눈을 만듭니다.

전제: docker (buildx 포함), gh CLI.

## Step 1. 빌더 준비 — driver의 차이부터

```bash
mkdir -p ~/ci-lab/buildkit && cd ~/ci-lab/buildkit

docker buildx ls        # 현재 빌더: default (driver: docker — 데몬 내장)

# CI 표준: docker-container driver (멀티아치·캐시 익스포트 가능)
docker buildx create --name lab --driver docker-container --use
docker buildx inspect --bootstrap | grep -E "Driver|Platforms"
```

예상: `Driver: docker-container`, Platforms에 amd64 외 여러 아치. ✅ buildkitd가 **컨테이너로 별도 실행**됐습니다(`docker ps | grep buildkit`으로 확인) — 이 분리가 멀티아치와 캐시 익스포트를 가능하게 합니다(theory §3).

## Step 2. 병렬 DAG 관찰 — 독립 스테이지는 동시에 돕니다

```bash
cat > Dockerfile <<'EOF'
# syntax=docker/dockerfile:1.7
FROM alpine AS stage-a
RUN sleep 5 && echo A > /a

FROM alpine AS stage-b
RUN sleep 5 && echo B > /b

FROM alpine
COPY --from=stage-a /a /a
COPY --from=stage-b /b /b
EOF

time docker buildx build --load -t lab:dag . 2>&1 | grep -E "^\#|DONE" | tail -15
```

예상: 전체 시간이 **~10초가 아니라 ~5초대** — stage-a와 stage-b가 의존 관계가 없어 솔버가 동시에 실행했습니다. 레거시 빌더라면 순차 10초+. ✅ Dockerfile은 위→아래 문서지만 실행은 **DAG**입니다(theory §2).

## Step 3. 캐시 키의 실체 — 내용 기반임을 증명

```bash
echo '{"name":"app","version":"1.0.0"}' > package.json
cat > Dockerfile <<'EOF'
# syntax=docker/dockerfile:1.7
FROM alpine
COPY package.json /pkg/
RUN echo "install step: $(date +%s)" && sleep 3
COPY . /src/
EOF

docker buildx build --load -t lab:cache . 2>&1 | grep -cE "CACHED" ; echo "--- 1차 빌드 완료"

# 실험 A: 파일을 touch만 (mtime 변경, 내용 동일)
touch package.json
docker buildx build --load -t lab:cache . 2>&1 | grep -E "\[2/4\]|\[3/4\]|CACHED" | head -5

# 실험 B: 내용 변경
sed -i 's/1.0.0/1.0.1/' package.json
docker buildx build --load -t lab:cache . 2>&1 | grep -E "\[2/4\]|\[3/4\]|CACHED" | head -5
```

예상: 실험 A는 COPY·RUN 모두 **CACHED**(mtime은 캐시 키에 안 들어감 — 내용 digest 기반), 실험 B는 COPY부터 미스 → RUN 연쇄 미스. ✅ 캐시 키 = 연산 + **입력 내용의 digest**(theory §2) — 04 규칙("자주 바뀌는 것을 아래로")의 원리 증명.

## Step 4. 캐시 익스포트 — min이 멀티스테이지를 배신하는 순간

GHA에서 registry 캐시로 실험합니다:

```bash
git init -q . && git config user.email l@e.com && git config user.name L
cat > Dockerfile <<'EOF'
# syntax=docker/dockerfile:1.7
FROM alpine AS build
RUN echo "expensive build step" && sleep 10 && echo out > /out

FROM alpine
COPY --from=build /out /out
EOF

mkdir -p .github/workflows
cat > .github/workflows/cache-modes.yml <<'EOF'
name: cache-modes
on: [push, workflow_dispatch]
permissions: { contents: read, packages: write }
jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        mode: [min, max]
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: 1차 빌드 (캐시 push, mode=${{ matrix.mode }})
        uses: docker/build-push-action@v6
        with:
          context: .
          tags: ghcr.io/${{ github.repository }}:test-${{ matrix.mode }}
          push: true
          cache-to: type=registry,ref=ghcr.io/${{ github.repository }}:cache-${{ matrix.mode }},mode=${{ matrix.mode }}
      - name: 캐시 비우고 2차 빌드 (캐시 pull만)
        run: |
          docker buildx prune -af >/dev/null
          START=$(date +%s)
          docker buildx build \
            --cache-from type=registry,ref=ghcr.io/${{ github.repository }}:cache-${{ matrix.mode }} \
            -t second . 2>&1 | grep -cE "CACHED" || true
          echo "mode=${{ matrix.mode }} 2차 빌드: $(( $(date +%s) - START ))초"
EOF

git add -A && git commit -qm "lab: buildkit cache modes"
gh repo create cicd-lab-buildkit --public --source=. --push >/dev/null
sleep 90
gh run view --log 2>/dev/null | grep -E "2차 빌드:" 
```

예상: `mode=max`는 2차 빌드가 수 초(expensive build step이 CACHED), **`mode=min`은 다시 10초+** — min은 최종 스테이지 레이어만 익스포트해서 build 스테이지 캐시가 없습니다. ✅ 멀티스테이지 + 캐시 익스포트 = **mode=max**(theory §4). "캐시를 붙였는데 안 먹어요"의 1번 원인.

## Step 5. attestation 맛보기 — 빌드가 증명서를 남깁니다

```bash
docker buildx build --provenance=true --sbom=true \
  -t ttl.sh/lab-$(uuidgen | cut -c1-8):1h --push . 2>&1 | tail -3
# ttl.sh: 익명 임시 레지스트리 (1h 후 자동 삭제 — 정리 불필요)

docker buildx imagetools inspect ttl.sh/lab-*:1h --raw 2>/dev/null | head -30 || \
  echo "직전 push한 태그로 inspect: docker buildx imagetools inspect <tag>"
```

예상: image index 안에 이미지 manifest와 나란히 `vnd.docker.reference.type: attestation-manifest` 항목. ✅ provenance/SBOM이 이미지 옆에 **첨부 파일처럼** 붙습니다 — 검증은 21에서.

## Step 6. 산출물 — 빌드 로그를 읽는 체크리스트

```markdown
# 빌드 로그 진단 카드
- CACHED가 기대 위치에서 사라짐   → 그 정점의 "입력"이 뭔지 역추적 (COPY 대상 내용? 부모 정점?)
- 독립 스테이지가 순차 실행       → driver가 docker(기본)인지, DAG가 실제로 독립인지
- CI만 매번 풀빌드                → 캐시 익스포트 없음 (ephemeral 러너)
- 캐시 붙였는데 중간 스테이지 미스 → mode=min (max로)
- 첫 줄 # syntax=                 → frontend 버전 — 새 문법이 안 되면 이것부터
```

## 정리

lab-02에서 같은 빌더로 멀티아치를 다룹니다. 빌더와 저장소 유지.
