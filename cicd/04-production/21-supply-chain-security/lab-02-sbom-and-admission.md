# Lab 02 — SBOM·스캔 게이트, 그리고 admission에서 증명 강제

성분표(SBOM)를 만들고 취약점 스캔을 CI 게이트로, 마지막으로 "서명 없는 이미지는 클러스터에 못 들어오게" 만듭니다.

전제: lab-01의 이미지(서명됨), kind, kubectl, syft/grype(`brew install syft grype` 또는 릴리스 바이너리).

## Step 1. SBOM 생성 — 성분표

```bash
cd ~/ci-lab/supply
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
IMAGE="ghcr.io/${REPO}:v1"

syft "$IMAGE" -o spdx-json > sbom.json 2>/dev/null
python3 -c "
import json
d = json.load(open('sbom.json'))
print('패키지 수:', len(d.get('packages',[])))
for p in d.get('packages',[])[:5]: print(' -', p.get('name'), p.get('versionInfo',''))
"
```

예상: alpine 베이스의 패키지 목록(musl, busybox, ...). ✅ 이미지의 **성분표** — 이 파일을 보관하면 신규 CVE 때 재스캔 없이 조회합니다(theory §4).

## Step 2. 소급 조회 시뮬레이션 — SBOM의 진짜 가치

```bash
# "오늘 musl에 치명적 CVE 발표!" — 어느 이미지가 영향받나요?
grep -l '"name": *"musl"' sbom.json && echo "→ 이 이미지 영향권 (재스캔 없이 판정)"

# 스캔은 SBOM에서 직접 (이미지 pull 불필요 — 빠름)
grype sbom:./sbom.json 2>/dev/null | tail -5
```

✅ Log4Shell급 사태의 첫 질문("우리 어디에 있지?")을 **분 단위**로 답하는 구조 — 이미지 수백 개를 재스캔하는 것과 SBOM 파일을 grep하는 것의 차이.

## Step 3. 스캔을 CI 게이트로

```bash
cat >> .github/workflows/release.yml <<'EOF'
      - name: SBOM 생성 + 보관
        uses: anchore/sbom-action@v0
        with:
          image: ghcr.io/${{ github.repository }}@${{ steps.build.outputs.digest }}
          format: spdx-json
          artifact-name: sbom.spdx.json
      - name: 취약점 게이트 (high 이상이면 실패)
        uses: anchore/scan-action@v6
        with:
          image: ghcr.io/${{ github.repository }}@${{ steps.build.outputs.digest }}
          severity-cutoff: high
          fail-build: true
EOF
git add -A && git commit -qm "ci: sbom + vuln gate" && git push -q
sleep 90
gh run view 2>/dev/null | tail -5
```

예상: alpine 베이스는 통과(취약점 적음). ✅ 게이트 배치가 핵심입니다 — **push 전이 아니라 push 후·배포 전**에 걸면 "취약한 이미지가 이미 레지스트리에" 있게 됩니다. 이 랩은 서명·스캔이 릴리스 워크플로 안(배포 전)에 있습니다.

## Step 4. admission — 증명 없는 이미지는 거절

```bash
kind create cluster --name supply -q
# Kyverno 설치 (admission 정책 엔진 — k8s 34의 VAP와 같은 자리, 서명 검증 내장)
kubectl create -f https://github.com/kyverno/kyverno/releases/latest/download/install.yaml >/dev/null 2>&1
kubectl -n kyverno wait --for=condition=ready pod -l app.kubernetes.io/component=admission-controller --timeout=180s

cat > verify-policy.yaml <<EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: require-signed-images }
spec:
  webhookTimeoutSeconds: 30
  rules:
    - name: require-cosign-keyless
      match: { any: [{ resources: { kinds: [Pod], namespaces: [default] } }] }
      verifyImages:
        - imageReferences: ["ghcr.io/${REPO}*"]
          failureAction: Enforce          # ★ 운영 도입은 Audit부터! (theory §6)
          attestors:
            - entries:
                - keyless:
                    subject: "https://github.com/${REPO}/.github/workflows/release.yml@*"
                    issuer: "https://token.actions.githubusercontent.com"
                    rekor: { url: https://rekor.sigstore.dev }
EOF
kubectl apply -f verify-policy.yaml
```

## Step 5. 게이트 동작 확인 — 서명된 것만 통과

```bash
DIGEST=$(cosign verify "ghcr.io/${REPO}:v1" \
  --certificate-identity-regexp=".*${REPO}.*" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  -o json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['critical']['image']['docker-manifest-digest'])")

# ① 서명된 이미지 (우리 워크플로가 서명) → admit
kubectl run signed --image="ghcr.io/${REPO}@${DIGEST}" 2>&1 | head -1

# ② 서명 안 된 이미지를 같은 경로처럼 위장 → 거절돼야 정상
kubectl run unsigned --image="ghcr.io/${REPO}:doesnotexist" 2>&1 | head -3
```

예상: ① `pod/signed created`, ② **에러 — 서명 검증 실패로 admission 거절**. ✅ 증명이 게이트가 됐습니다(theory §5): CI가 서명을 만들고(생산자), admission이 신원을 검증합니다(소비자 최후 방어선). 14의 GitOps와 합치면 Git 무결성 + 아티팩트 무결성이 함께 닫힙니다.

## Step 6. 도입 순서 연습 — 처음부터 Enforce는 사고입니다

```bash
# 만약 이 정책을 기존 클러스터 전체에 Enforce로 켰다면?
#   → 서명 없는 기존 이미지의 모든 Pod 재시작이 거절 → 노드 교체·HPA 스케일아웃 전부 실패
cat <<'EOF'
운영 도입 순서 (k8s 34의 VAP와 동일한 지혜):
  1. failureAction: Audit — 위반을 PolicyReport로 수집만
  2. kubectl get policyreport -A 로 위반 목록 → 팀별 서명 이행 기간
  3. 신규 네임스페이스만 Enforce
  4. 전체 Enforce + 명시적 예외 목록 (kube-system, 서드파티 — 각 예외에 사유 주석)
EOF
```

## Step 7. 산출물 — 공급망 계층 방어 지도

```markdown
# 우리 파이프라인의 공급망 방어 (01~21 총정리)
소스      SHA 고정(03), 브랜치 보호(02), dist 검증(18)
의존성    잠금 파일, npm audit(18), 레지스트리 우선순위
빌드      격리된 러너(08), provenance(19) — SLSA 등급
아티팩트  다이제스트(04), keyless 서명 + Rekor(21)
캐시      쓰기 신뢰 경계(20)
배포 관문 admission 서명 검증(21) ← 최후 방어선
소급 대응 SBOM 보관(21) — 신규 CVE의 분 단위 영향 조회
```

## 정리

```bash
bash cleanup.sh
```
