# Lab 01 — keyless 서명과 검증: OIDC가 서명이 되는 순간

GHA에서 이미지를 빌드·서명하고, "어느 워크플로가 서명했나"를 검증합니다 — 07의 OIDC가 서명 신원으로 재등장합니다.

전제: gh CLI, docker, cosign(`brew install cosign` 또는 릴리스 바이너리).

## Step 1. 서명하는 릴리스 워크플로

```bash
mkdir -p ~/ci-lab/supply/.github/workflows && cd ~/ci-lab/supply
git init -q . && git config user.email l@e.com && git config user.name L

cat > Dockerfile <<'EOF'
FROM alpine
CMD ["echo", "signed artifact"]
EOF

cat > .github/workflows/release.yml <<'EOF'
name: release
on: [push, workflow_dispatch]
permissions:
  contents: read
  packages: write
  id-token: write          # ★ 07의 그 권한 — OIDC 토큰이 서명 신원이 됩니다
jobs:
  build-sign:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: 빌드 + push (다이제스트 확보 — 04)
        id: build
        uses: docker/build-push-action@v6
        with:
          context: .
          tags: ghcr.io/${{ github.repository }}:v1
          push: true
          provenance: true            # 19의 provenance — SLSA L1 재료
      - uses: sigstore/cosign-installer@v3
      - name: keyless 서명 (키 없음!)
        run: cosign sign --yes ghcr.io/${{ github.repository }}@${{ steps.build.outputs.digest }}
        # 내부에서: OIDC 토큰 → Fulcio 인증서(10분) → 서명 → Rekor 기록 (theory §3)
      - name: 다이제스트 출력 (검증용)
        run: echo "DIGEST=${{ steps.build.outputs.digest }}"
EOF

git add -A && git commit -qm "release with keyless signing"
gh repo create cicd-lab-supply --public --source=. --push >/dev/null
sleep 90
gh run view --log 2>/dev/null | grep -E "DIGEST=|tlog entry" | head -3
```

예상: `tlog entry created with index: NNNNN`(Rekor 기록!)과 DIGEST 출력. ✅ 서명에 **키가 등장하지 않았습니다** — `id-token: write`(07)가 서명 자격의 전부입니다.

## Step 2. 검증 — 키가 아니라 신원을 검증합니다

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
DIGEST=$(gh run view --log 2>/dev/null | grep -oE "DIGEST=sha256:[a-f0-9]+" | head -1 | cut -d= -f2)
IMAGE="ghcr.io/${REPO}@${DIGEST}"

# 올바른 신원으로 검증
cosign verify "$IMAGE" \
  --certificate-identity-regexp="^https://github.com/${REPO}/.github/workflows/release.yml@.*" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  2>&1 | head -5
```

예상: `Verification succeeded` + 인증서의 subject(워크플로 경로)·issuer가 표시. ✅ 검증 질문은 "**이 저장소의 release.yml이 서명했는가**"다 — 07의 sub 클레임 설계가 그대로 서명 신원 조건.

## Step 3. 반례 — 다른 신원은 거절됩니다

```bash
# 다른 저장소/워크플로를 신원으로 주장하면?
cosign verify "$IMAGE" \
  --certificate-identity-regexp="^https://github.com/someone-else/repo/.*" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  2>&1 | tail -2
```

예상: `no matching signatures` — 서명은 있지만 **그 신원의 서명이 아닙니다**. ✅ 공격자가 자기 저장소에서 서명한 이미지를 우리 것으로 속일 수 없습니다 — 신원이 인증서에 박혀 있으므로.

## Step 4. Rekor — 공개 장부에서 서명 기록 조회

```bash
# 서명이 남긴 투명성 로그 (은폐·부인 불가)
cosign verify "$IMAGE" \
  --certificate-identity-regexp=".*${REPO}.*" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  -o json 2>/dev/null | python3 -c "
import json,sys
d = json.load(sys.stdin)
b = d[0]['optional']
print('Rekor logIndex:', d[0].get('Bundle',{}).get('Payload',{}).get('logIndex', 'n/a'))
print('서명 신원:', b.get('Subject', b.get('subject','')))
print('issuer  :', b.get('Issuer', b.get('1.3.6.1.4.1.57264.1.1','')))
"
```

예상: Rekor logIndex(공개 로그의 위치)와 신원. ✅ **모든 keyless 서명은 공개 기록을 남깁니다** — 나중에 "그때 그 서명"의 존재와 시점을 제3자가 검증 가능(10분짜리 인증서가 사후에도 유효한 이유, theory §3).

## Step 5. provenance 검증 — 19의 증명서를 소비

```bash
# 이미지에 첨부된 provenance attestation 확인 (19에서 만들던 것)
cosign download attestation "$IMAGE" 2>/dev/null | head -1 | \
  python3 -c "
import json,sys,base64
env = json.load(sys.stdin)
pred = json.loads(base64.b64decode(env['payload']))
print('빌드 타입:', pred.get('predicateType', pred.get('_type','')))
" 2>/dev/null || docker buildx imagetools inspect "ghcr.io/${REPO}:v1" | grep -A2 -i attestation | head -5
```

예상: provenance(SLSA) attestation의 존재. ✅ "이 이미지가 어떤 소스·빌더에서 나왔나"의 기록 — 18의 verify-dist가 답한 질문의 이미지판이며, SLSA L2+ 경로(GitHub Artifact Attestations)의 재료입니다.

## Step 6. 산출물 — 서명 파이프라인 카드

```markdown
# keyless 서명 체크리스트
- [x] permissions: id-token: write (07 — 이것이 서명 자격)
- [x] 다이제스트로 서명 (태그는 움직입니다 — 04)
- [x] tlog entry 확인 (Rekor 기록)
- [x] 검증 = certificate-identity(워크플로) + issuer — 키가 아니라 신원
- [x] provenance 첨부 (19) — SLSA 재료
- [ ] lab-02: SBOM + admission에서 이 검증을 강제
```

## 정리

lab-02에서 이 이미지로 SBOM·admission을 실습합니다. 저장소·이미지 유지.
