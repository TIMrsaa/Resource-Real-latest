# Lab 01 — 실행 모델을 실험으로 해부하기

guide가 예고한 네 미스터리를 **직접 재현하고 원인을 구조로 설명**합니다. YAML을 복사하는 대신, 왜 그렇게 써야 하는지 실패로 배웁니다.

## Step 1. 실험 저장소

```bash
mkdir -p ~/ci-lab/gha && cd ~/ci-lab/gha
git init -q && git config user.email l@e.com && git config user.name L
echo "# gha lab" > README.md && git add -A && git commit -qm "init" && git branch -M main
gh repo create cicd-lab-gha --public --source=. --push
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
mkdir -p .github/workflows
```

## Step 2. 미스터리 ① — 스텝 간 변수가 사라집니다

```bash
cat > .github/workflows/mystery.yml <<'EOF'
name: mystery
on: workflow_dispatch
jobs:
  steps-demo:
    runs-on: ubuntu-latest
    steps:
      - name: 셸 변수로 시도 (실패할 것)
        run: export MY_VAR="hello"
      - name: 읽기 시도
        run: echo "셸 변수 = [$MY_VAR]"

      - name: GITHUB_ENV로 시도
        run: echo "MY_VAR2=world" >> "$GITHUB_ENV"
      - name: 읽기
        run: echo "GITHUB_ENV = [$MY_VAR2]"

      - name: 파일시스템은 공유되나요?
        run: echo "artifact content" > shared.txt
      - name: 파일 읽기
        run: cat shared.txt
EOF
git add -A && git commit -qm "ci: mystery workflow" && git push -q
gh workflow run mystery.yml && sleep 25
gh run list --workflow=mystery.yml --limit 1
gh run view --log | grep -E "셸 변수 =|GITHUB_ENV =|artifact content" || gh run view --log-failed | head
```

예상:

```
셸 변수 = []              ← 사라짐! 각 스텝은 새 셸 프로세스
GITHUB_ENV = [world]      ← 파일에 적으니 전달됨
artifact content          ← 파일시스템은 같은 잡 안에서 공유
```

✅ **경계는 "셸 프로세스"이지 "머신"이 아닙니다** (theory §1). 스텝은 같은 러너·같은 디스크를 쓰지만, 각 `run:`은 새 셸입니다.

## Step 3. 미스터리 ② — 잡을 나눴더니 파일이 없습니다

```bash
cat > .github/workflows/jobs.yml <<'EOF'
name: jobs
on: workflow_dispatch
jobs:
  producer:
    runs-on: ubuntu-latest
    outputs:
      msg: ${{ steps.gen.outputs.msg }}          # ① 작은 값
    steps:
      - id: gen
        run: |
          echo "msg=hello-from-producer" >> "$GITHUB_OUTPUT"
          echo "big file content" > build.txt
      - uses: actions/upload-artifact@v4          # ② 파일
        with: { name: build, path: build.txt }

  consumer:
    needs: producer                                # ③ 순서
    runs-on: ubuntu-latest
    steps:
      - name: 파일이 그냥 있을까요? (없습니다)
        run: |
          cat build.txt 2>&1 || echo "→ 없음: 잡은 서로 다른 러너다"
      - name: outputs는 옵니다
        run: echo "outputs = ${{ needs.producer.outputs.msg }}"
      - uses: actions/download-artifact@v4
        with: { name: build }
      - name: 이제 있습니다
        run: cat build.txt
EOF
git add -A && git commit -qm "ci: jobs demo" && git push -q
gh workflow run jobs.yml && sleep 40
gh run view --log 2>/dev/null | grep -E "없음:|outputs =|big file content" | head
```

✅ 잡은 **다른 VM**입니다. 전달 수단은 outputs(문자열)와 artifacts(파일)뿐 — 이 비용 때문에 잡을 무작정 쪼개면 오히려 느려집니다.

## Step 4. 미스터리 ③ — 인젝션 취약점 재현 (안전한 형태로)

```bash
cat > .github/workflows/inject.yml <<'EOF'
name: inject-demo
on:
  workflow_dispatch:
    inputs:
      title:
        description: 'PR 제목을 흉내 (예: a"; echo PWNED; #)'
        default: "normal title"
jobs:
  unsafe:
    runs-on: ubuntu-latest
    steps:
      - name: 취약 — 표현식이 셸 코드가 됩니다
        run: |
          echo "제목: ${{ github.event.inputs.title }}"
  safe:
    runs-on: ubuntu-latest
    steps:
      - name: 안전 — env 경유
        env:
          TITLE: ${{ github.event.inputs.title }}
        run: |
          echo "제목: $TITLE"
EOF
git add -A && git commit -qm "ci: injection demo" && git push -q

# 악의적 입력으로 실행
gh workflow run inject.yml -f 'title=x"; echo PWNED_INJECTION; #'
sleep 30
gh run view --log 2>/dev/null | grep -E "PWNED_INJECTION|제목:" | head -4
```

예상: `unsafe` 잡의 로그에 **`PWNED_INJECTION`이 출력**되고(공격자의 명령이 실행됐습니다), `safe` 잡은 그 문자열을 **값으로만** 출력합니다.

✅ 실제 공격에서는 PR 제목·브랜치명·커밋 메시지가 이 자리에 옵니다. 방어는 단순합니다: **사용자 입력은 언제나 `env:`로.**

## Step 5. 미스터리 ④ — 컨텍스트를 눈으로

```bash
cat > .github/workflows/context.yml <<'EOF'
name: context
on:
  workflow_dispatch:
  pull_request:
jobs:
  show:
    runs-on: ubuntu-latest
    permissions:
      contents: read          # ★ 최소 권한 선언 (기본을 좁힙니다)
    steps:
      - name: 이 실행은 무엇인가
        run: |
          echo "event      = ${{ github.event_name }}"
          echo "ref        = ${{ github.ref }}"
          echo "sha        = ${{ github.sha }}"
          echo "actor      = ${{ github.actor }}"
          echo "run_id     = ${{ github.run_id }}"
      - name: 시크릿은 존재하는가 (값은 안 보입니다)
        run: |
          if [ -n "${{ secrets.GITHUB_TOKEN }}" ]; then echo "GITHUB_TOKEN: 있음"; fi
          echo "마스킹 확인: ${{ secrets.GITHUB_TOKEN }}"    # → *** 로 나옵니다
EOF
git add -A && git commit -qm "ci: context" && git push -q
gh workflow run context.yml && sleep 25
gh run view --log 2>/dev/null | grep -E "event |ref |actor |마스킹" | head -5
```

✅ 시크릿은 로그에서 `***`로 마스킹됩니다 — 다만 **인코딩해 출력하면 우회**된다는 것을 기억하세요(신뢰할 수 없는 액션을 쓰지 말아야 하는 이유, 21).

## Step 6. 실행 모델 정리 노트 (산출물)

```markdown
# GitHub Actions 실행 모델 — 내가 확인한 것
| 질문 | 답 | 근거 실험 |
|------|----|----------|
| 스텝 간 셸 변수? | 안 넘어감 (새 셸 프로세스) | Step 2 |
| 스텝 간 파일? | 넘어감 (같은 러너 FS) | Step 2 |
| 잡 간 파일? | 안 넘어감 → artifacts | Step 3 |
| 잡 간 값? | outputs + needs | Step 3 |
| 표현식의 위험? | 셸 파싱 전 치환 → 인젝션. env로 방어 | Step 4 |
| 시크릿 마스킹? | 자동(***), 인코딩 우회 가능 | Step 5 |
```

## 정리

실험 워크플로는 lab-02에서 대체됩니다. 저장소는 유지.
