# 이론 — 재사용 3수단, 시크릿의 경계, environments

> **🌱 17세 눈높이 비유: 학교의 수업 자료**
> - **composite action** = 여러 선생님이 쓰는 **한 묶음의 프린트물** — 수업(잡) 안에서 나눠줍니다. 자체적으로 교실을 열 수는 없습니다
> - **reusable workflow** = 아예 **수업 하나를 통째로 위탁** — "3반의 수학 수업은 본관의 표준 수업으로 대체합니다". 교실(러너)이 새로 열립니다
> - **starter workflow** = 신규 교사에게 주는 **수업계획서 템플릿** — 복사해서 각자 고칩니다. 이후 갱신은 각자 몫
> - **secrets: inherit** = "본관 수업에 우리 반 금고 열쇠를 전부 맡깁니다" — 편하지만, 본관이 털리면 우리 금고도 털립니다
> - **environment** = 시험 답안지 보관실 — **들어가려면 교감 승인**이 필요하고, 열쇠는 그 방 안에만 있습니다

---

## 1. 재사용 3수단 — 선택 기준

| | composite action | reusable workflow | starter workflow |
|---|---|---|---|
| 위치 | `action.yml` (저장소/경로) | `.github/workflows/*.yml` | `.github/workflow-templates/` (조직) |
| 호출 | `uses:` (스텝 자리) | `uses:` (**잡** 자리) | 복사됨 (일회성) |
| 만드는 것 | 스텝 묶음 (같은 러너) | **잡들** (새 러너) | 파일 |
| `runs-on` 지정 | ✘ (호출한 잡의 러너) | ✔ | ✔ |
| 시크릿 접근 | 호출자가 넘겨줘야(`with:`) | `secrets:` 또는 `inherit` | — |
| 중첩 | 액션 안에 액션 ✔ | 최대 4단계 | — |
| 갱신 전파 | 자동(버전 참조) | 자동 | **수동** (복사본이니까) |

선택 규칙:

```
"몇 개의 스텝을 묶고 싶다"          → composite action
"CI 잡 전체(러너 선택 포함)를 표준화" → reusable workflow
"새 저장소의 출발점을 제공"          → starter workflow
```

**흔한 실수**: composite action으로 잡 수준의 것(matrix, services, permissions)을 하려다 막힙니다 — 그것들은 잡의 속성이지 스텝의 속성이 아닙니다.

## 2. `workflow_call` 인터페이스 설계

```yaml
# .github/workflows/reusable-ci.yml (호출당하는 쪽)
on:
  workflow_call:
    inputs:
      python-version: { type: string, default: "3.12" }
      run-integration: { type: boolean, default: false }
    secrets:
      ECR_ROLE:        { required: false }        # ★ 명시적 선언 = 계약
    outputs:
      image-digest:
        value: ${{ jobs.build.outputs.digest }}
jobs:
  build:
    runs-on: ubuntu-latest
    outputs: { digest: ${{ steps.p.outputs.digest }} }
    steps: [...]
```

```yaml
# 호출하는 쪽
jobs:
  ci:
    uses: my-org/.github/.github/workflows/reusable-ci.yml@<SHA>   # ★ SHA 고정
    with:
      python-version: "3.13"
    secrets:
      ECR_ROLE: ${{ secrets.ECR_ROLE }}          # 필요한 것만 (inherit 아님)
```

### 시크릿 전달의 두 방식과 그 폭발 반경

| | `secrets: inherit` | 명시적 전달 |
|---|---|---|
| 넘어가는 것 | **호출자의 모든 시크릿** | 지정한 것만 |
| 편의 | 최고 | 한 줄씩 |
| 위험 | 재사용 워크플로가 탈취되면 전부 유출 | 최소 권한 |

규칙: **`inherit`는 같은 저장소 안에서만.** 다른 저장소(조직 공용)의 워크플로에는 필요한 시크릿만 명시적으로. 이것이 재사용의 대가입니다(guide의 kubefed 교훈).

## 3. 호출 제약 — 알아둘 규칙들

- reusable workflow 안에서는 다른 reusable workflow를 부를 수 있습니다 (총 **4단계**까지)
- reusable을 호출하는 잡에는 `steps:`를 쓸 수 없습니다 — 그 잡은 통째로 위임됩니다
- `strategy: matrix`는 호출하는 쪽에서 가능 (매트릭스 × reusable = 잡이 여럿 생성)
- `GITHUB_TOKEN`의 권한은 **호출자의 `permissions:`** 를 따릅니다 (호출당하는 쪽이 더 넓힐 수 없습니다 — 안전한 설계)
- `env`는 상속되지 않습니다 (inputs로 넘겨라)

## 4. 동적 매트릭스 — `fromJSON`

매트릭스를 하드코딩하지 않고 **잡이 계산**하게 합니다:

```yaml
jobs:
  discover:
    runs-on: ubuntu-latest
    outputs:
      services: ${{ steps.d.outputs.services }}
    steps:
      - uses: actions/checkout@v4
      - id: d
        run: |
          # 예: 변경된 디렉터리만 (20의 affected 빌드 씨앗)
          echo "services=$(ls services | jq -R -s -c 'split("\n")[:-1]')" >> "$GITHUB_OUTPUT"

  build:
    needs: discover
    strategy:
      matrix:
        service: ${{ fromJSON(needs.discover.outputs.services) }}
    runs-on: ubuntu-latest
    steps:
      - run: echo "building ${{ matrix.service }}"
```

주의: 매트릭스가 **0개**면 잡이 아예 생성되지 않습니다 — 후속 잡의 `needs`가 skipped가 되어 게이트가 이상해집니다. 03의 수렴 잡 + `if: always()` 패턴이 여기서 필수가 됩니다.

## 5. Environments — 배포 통제의 선언적 형태

```yaml
jobs:
  deploy-prod:
    environment:
      name: production
      url: https://app.example.com     # 배포 결과 링크(UI에 표시)
    runs-on: ubuntu-latest
    steps: [...]
```

environment에 붙일 수 있는 보호 규칙:

| 규칙 | 효과 |
|------|------|
| **required reviewers** | 승인 전까지 잡이 **대기**(러너 점유 없음) — 01의 "배포 버튼" |
| **wait timer** | N분 대기 — 취소할 기회(실수 배포 방어) |
| **deployment branches** | `main`(또는 태그)에서만 배포 가능 |
| **environment secrets** | 그 환경의 잡에서만 읽히는 시크릿 |
| environment variables | 환경별 설정(엔드포인트 등) |

핵심 성질 둘:

1. **시크릿 스코프**: 프로덕션 자격증명을 `production` 환경에만 두면, PR의 CI 잡은 그것에 접근할 수 없습니다 — 03의 포크 PR 위험을 구조적으로 차단
2. **승인 대기 중에는 러너를 쓰지 않습니다** — 비용 없이 며칠도 대기 가능

## 6. 조직 표준 배포 — `.github` 저장소

```
my-org/.github/
├─ .github/workflows/reusable-ci.yml        ← 조직 공용 reusable workflow
├─ .github/workflow-templates/              ← starter workflow (신규 저장소 제안)
│   ├─ node-ci.yml
│   └─ node-ci.properties.json
└─ profile/README.md
```

거버넌스 손잡이(조직 설정):

- **허용 액션 목록**: 특정 org의 액션만 / 검증된 크리에이터만 / SHA 고정 강제
- 기본 `GITHUB_TOKEN` 권한을 **읽기 전용**으로 (필요한 워크플로가 명시적으로 확장)
- reusable workflow 접근 범위(같은 org만)

## 7. 소스/도구에서 확인하기

- Reusable workflows: https://docs.github.com/actions/using-workflows/reusing-workflows
- Composite actions: https://docs.github.com/actions/creating-actions/creating-a-composite-action
- Environments & deployment protection rules: https://docs.github.com/actions/deployment/targeting-different-environments
- `actionlint` — 워크플로 정적 검사(인젝션·문법·시크릿 오용)

## 요약 카드

| 질문 | 답 |
|------|----|
| 스텝 묶음 vs 잡 표준화? | composite action vs reusable workflow |
| composite의 제약? | `runs-on`·matrix·services 불가 (잡의 속성이라) |
| `secrets: inherit`의 위험? | 호출자의 **모든** 시크릿 전달 — 외부 저장소엔 명시 전달 |
| 재사용 워크플로 버전? | 태그 아닌 **SHA 고정**(03의 공급망 규율) |
| 동적 매트릭스? | 앞 잡의 outputs → `fromJSON` (빈 배열 주의) |
| 승인 게이트? | environment + required reviewers (대기 중 러너 미점유) |
| 프로덕션 시크릿 격리? | environment secrets — PR CI에서 접근 불가 |
