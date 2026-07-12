# GitHub Actions 치트시트

> 03의 실행 모델(이벤트→워크플로→잡→스텝)이 지도입니다. 워크플로 YAML의 모든 줄은 그 4층 중 하나에 속합니다.

## 워크플로 뼈대 — 안전 기본값 (03·24)

```yaml
name: ci
on:
  pull_request:                        # 포크 PR: 시크릿 미제공 (신뢰 경계 — 03)
  push: { branches: [main] }
permissions: { contents: read }        # ★ 최상위 명시 — 24의 정책 검사 대상 1호
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true             # CI만! 배포 워크플로는 금지 (25 카드 3)
```

## 자주 쓰는 컨텍스트·표현식 (03)

```yaml
${{ github.sha }}                      # 커밋 — 이미지 태그로 (04)
${{ github.event_name }}               # 트리거 구분
${{ github.event.pull_request.base.sha }}   # affected 계산의 base (20)
${{ secrets.X }} / ${{ vars.X }}       # 시크릿(마스킹됨) / 평문 변수
${{ needs.build.outputs.digest }}      # 잡 간 데이터 (needs 필수)
# ⚠️ 표현식은 셸 파싱 전 치환 — 사용자 입력은 env 경유 (03 인젝션)
env: { TITLE: "${{ github.event.pull_request.title }}" }
run: echo "$TITLE"
```

## 잡 제어

```bash
needs: [a, b]                          # 의존 — "산출물을 쓰는가요?" 아니면 지워라 (23 critical path)
if: always()                           # 게이트 잡 (스킵 판정 — 20)
if: github.event_name == 'push'
strategy: { fail-fast: false, matrix: { ... } }   # flaky 사냥 때 false (25 lab-02)
timeout-minutes: 15                    # 기본 360분 — 반드시 줄여라
environment: production                # 승인·브랜치 제한 (06·24 SoD)
```

## OIDC → AWS (07)

```yaml
permissions: { id-token: write, contents: read }
steps:
  - uses: aws-actions/configure-aws-credentials@v4   # 실전: SHA 고정 (03)
    with:
      role-to-assume: arn:aws:iam::<acct>:role/gha-deploy
      aws-region: ap-northeast-2
# 신뢰 정책 sub 예: repo:org/repo:environment:production (좁게! — 07)
```

## 빌드·캐시·서명 (04·19·21)

```yaml
- uses: docker/setup-buildx-action@v3          # docker-container driver (19)
- uses: docker/build-push-action@v6
  with:
    push: true
    tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
    cache-to: type=gha,mode=max                # 멀티스테이지는 max! (19)
    cache-from: type=gha
    provenance: true                           # SLSA 재료 (19·21)
- uses: sigstore/cosign-installer@v3
- run: cosign sign --yes $IMAGE@${{ steps.build.outputs.digest }}   # keyless (21)
```

## 게이트 패턴 모음

```yaml
# ① 단일 ci 게이트 (03·20) — required check는 이것 하나
ci:
  needs: [detect, test, build]
  if: always()
  steps:
    - run: |
        [[ "${{ needs.test.result }}" =~ ^(success|skipped)$ ]] || exit 1

# ② affected 동적 매트릭스 (20) — fetch-depth: 0 잊지 말 것
# ③ 시크릿 스캔 (22): gitleaks-action / ④ 정책 검사 (24): conftest
```

## 디버깅 (25·26)

```bash
gh run list --workflow=ci --limit 5
gh run view <id> --log | grep -i error
gh run view <id> --log --job <job-id>
gh api repos/{owner}/{repo}/actions/runs/<id>/jobs --jq '.jobs[] | "\(.name) \(.conclusion)"'
# queue time = started_at - created_at (23) / self-hosted 러너 내부는 _diag (26)
gh workflow run ci && gh run watch                 # 수동 트리거 + 관찰
# 3질문 먼저: 항상/간헐? 나만/전원? 무엇이 변했나요? (25)
```

## 러너 (08)

```yaml
runs-on: ubuntu-latest                 # 호스티드 (잡마다 새 VM)
runs-on: ubuntu-24.04-arm              # 네이티브 arm64 (19 멀티아치)
runs-on: [self-hosted, linux, x64]     # 셀프호스티드 — 퍼블릭 저장소 금지! (08)
container: node:20                     # 잡을 컨테이너에서 (환경 고정 — 25 카드 5)
```
