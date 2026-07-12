# 이론 — affected 계산, 태스크 그래프와 캐시, Bazel, CI 통합

> **🌱 17세 눈높이 비유: 아파트 단지 정전 점검**
> - 모노레포 = 한 단지에 건물 여러 동 (서비스들) + 공용 발전기 (공유 라이브러리)
> - 어떤 동의 배선을 고쳤습니다 → 어디를 점검해야 하나요?
> - **전부 점검** = 단지 전체 소등 후 40분 점검 — 안전하지만 매번 이러면 아무도 일 못 함
> - **path filter** = "고친 동만 점검" — 그런데 **공용 발전기**를 고쳤다면? 발전기 방만 점검하고 넘어가면, 발전기에 연결된 모든 동이 위험 (침묵의 회귀)
> - **의존성 그래프 affected** = 배선도를 보고 "발전기 → 연결된 A동·C동·E동까지 점검" — 정확히 영향권만
> - **캐시** = "B동은 지난 점검 이후 아무것도 안 바뀜 → 지난 점검표 재사용" (같은 입력 = 같은 결과)

---

## 1. 문제 정의 — 모노레포 CI의 유일한 질문

커밋 하나가 왔습니다. 무엇을 빌드·테스트해야 하나요?

| 전략 | 낭비(과잉 실행) | 누락(침묵의 회귀) | 비용 |
|---|---|---|---|
| 전부 실행 | 최대 (커밋당 전체) | 없음 | 피드백 루프 붕괴(01) |
| path filter | 적음 | **있음** (의존성 무지) | 설정 몇 줄 |
| 그래프 affected | 거의 없음 | 거의 없음* | 도구 도입(Nx/Turbo) |
| Bazel | 최소 (타깃 단위) | 최소 | 빌드 전면 재작성 |

*그래프가 못 보는 암묵 의존(전역 설정, 코드 생성, 환경)은 남습니다 — §5.

정확도의 축은 하나입니다: **"영향"을 어떤 해상도로 아는가** — 폴더인가, 프로젝트 그래프인가, 빌드 타깃인가.

## 2. 1단계: path filter — 싸고 위험한 근사

```yaml
# GHA 내장: 워크플로 자체를 조건 실행
on:
  push:
    paths: ['services/api/**']       # api가 바뀔 때만 이 워크플로

# 잡 단위: dorny/paths-filter로 잡별 분기
- uses: dorny/paths-filter@v3
  id: chg
  with:
    filters: |
      api: ['services/api/**']
      web: ['services/web/**']
- if: steps.chg.outputs.api == 'true'
  run: npm test -w services/api
```

**치명적 맹점**: `libs/shared/**`가 바뀌면? api와 web 둘 다 shared를 import하는데, path filter는 그것을 모릅니다. 필터에 `libs/shared/**`를 api·web 양쪽에 수동으로 추가할 수 있지만 — 그 목록은 **의존성 그래프의 수동 사본**이고, 사본은 반드시 낡습니다(새 import 하나가 필터 갱신을 요구). path filter는 의존성이 없는 독립 폴더(docs/, 인프라 매니페스트)에만 안전합니다.

## 3. 2단계: 프로젝트 그래프 affected — Nx / Turborepo

도구가 소스에서 그래프를 **자동 추출**합니다 (package.json workspaces·import 분석):

```
        libs/shared ──▶ services/api ──▶ (배포)
                   └──▶ services/web ──▶ (배포)

affected(변경) = 변경 파일의 소유 프로젝트 + 그 역방향 전이 의존자 전부
  shared 변경  → {shared, api, web}     ← path filter가 놓치던 것
  api만 변경   → {api}
```

```bash
# Turborepo: main 대비 영향받은 것만 빌드·테스트
turbo run test --filter='...[origin/main]'
# Nx: 동형
nx affected -t test --base=origin/main
```

### 태스크 그래프와 캐시 — 19와 같은 원리

```
태스크 해시 = hash(소스 파일들 + 의존 프로젝트의 출력 + 설정 + 환경변수 선언)
  같은 해시 → 저장된 출력(dist/, 로그)을 꺼내 재생 ("FULL TURBO" / Nx cache hit)
  원격 캐시 → 이 저장소를 팀·CI가 공유: "동료가 이미 빌드한 것은 아무도 다시 안 빌드"
```

19의 BuildKit(연산+입력 digest → 레이어 재사용)과 **동일한 아이디어, 다른 층**입니다. 캐시가 옳으려면 태스크가 선언된 입력에만 의존해야 합니다 — 선언 안 된 입력(환경변수, 시계, 네트워크)이 결과를 바꾸면 캐시 오염(25의 장애 시나리오).

## 4. 3단계: Bazel — 밀폐(hermetic) 빌드의 대가와 보상

```
BUILD 파일이 타깃(라이브러리·바이너리·테스트)과 의존성을 명시적으로 선언
  → 파일보다 촘촘한 해상도 (한 패키지 안에서도 타깃 단위 affected)
  → 밀폐: 선언 안 된 입력 접근을 차단 (샌드박스) — 캐시가 "믿을 수 있게" 됨
  → 원격 캐시 + 원격 실행: 수만 타깃을 팜에서 병렬 (Google 내부 Blaze의 오픈소스판)
```

| | Nx/Turborepo | Bazel |
|---|---|---|
| 의존성 선언 | 자동 추출 (import 분석) | 수동 BUILD 파일 (Gazelle로 일부 자동화) |
| 밀폐성 | 관례 (어기면 캐시 오염) | **강제** (샌드박스) |
| 생태계 | JS/TS 중심 | 다언어 (Go/Java/C++/...) |
| 도입 비용 | 낮음 (기존 npm scripts 위에) | **전면 재작성** 수준 |
| 자리 | 대부분의 팀 | 수천 명·다언어·초대형 |

Bazel의 교훈은 도입 여부와 무관하게 유효합니다: **캐시의 신뢰도는 입력 선언의 정직함에 비례합니다**. Nx/Turbo에서도 이 원칙(태스크 입력을 정확히 선언)을 지키는 만큼 캐시가 안전해집니다.

## 5. affected가 못 보는 것 — 그래프의 한계

```
- 전역 설정: 루트 tsconfig/lint 설정 변경 → 사실상 전부 affected (도구는 대개 이렇게 처리 — 갑자기 전체 빌드가 도는 이유)
- 코드 생성: proto → 생성 코드 — 생성 단계가 그래프에 없으면 끊긴 선
- 런타임 계약: A 서비스의 API 응답 변경 — B는 코드 의존이 없지만 계약 의존 (그래프 밖 → 계약 테스트로)
- 환경: Node 버전, OS — 태스크 해시에 넣지 않으면 캐시가 낡은 출력 재생
```

그래프는 **코드 의존성**의 지도입니다. 계약·데이터·인프라 의존은 다른 도구(계약 테스트, e2e — 05의 피라미드 상층)가 맡습니다.

## 6. CI 통합 — 동적 매트릭스와 required check 함정

### affected → 매트릭스 (06의 동적 매트릭스의 완성형)

```yaml
jobs:
  detect:
    outputs: { projects: ${{ steps.aff.outputs.projects }} }
    steps:
      - id: aff
        run: echo "projects=$(turbo ls --affected --output=json | jq -c '.packages.items|map(.name)')" >> "$GITHUB_OUTPUT"
  build:
    needs: detect
    if: needs.detect.outputs.projects != '[]'
    strategy:
      matrix: { project: ${{ fromJSON(needs.detect.outputs.projects) }} }
    steps:
      - run: turbo run build --filter=${{ matrix.project }}
```

### required check 함정 — 스킵은 통과가 아닙니다

```
브랜치 보호(02)에 required check "build (api)"를 걸었습니다
→ api가 affected가 아닌 PR: 그 잡이 스킵됨
→ GitHub: required check가 "expected" 상태로 영원히 대기 → PR 머지 불가 ❌
```

해법은 03에서 이미 만들었습니다 — **단일 `ci` 게이트**:

```yaml
  ci:                                   # required check는 이것 '하나만'
    needs: [detect, build]
    if: always()                        # 스킵돼도 실행
    steps:
      - run: |
          [[ "${{ needs.build.result }}" == "success" || "${{ needs.build.result }}" == "skipped" ]] \
            && echo OK || exit 1
```

매트릭스가 어떻게 변해도(잡 이름이 바뀌어도, 스킵돼도) required check는 `ci` 하나로 불변 — 03의 게이트 패턴이 모노레포에서 구조적 필수가 되는 지점.

## 7. 배포까지 — affected의 끝

```
affected 계산 → 영향 서비스만 빌드 (이미지 태그 = 커밋 SHA, 04)
             → 영향 서비스의 매니페스트만 갱신 (GitOps 저장소, 14)
             → ArgoCD ApplicationSet이 앱 단위로 sync (14) — 안 바뀐 서비스는 배포 자체가 없음
```

모노레포 + GitOps에서 "서비스별 독립 배포"가 성립하는 구조입니다 — 저장소는 하나지만 배포 단위는 그래프가 정합니다.

## 8. 소스/도구에서 확인하기

- Turborepo(태스크 해시·원격 캐시): https://turborepo.com/docs — `crafting-your-repository/caching`
- Nx affected: https://nx.dev/ci/features/affected
- Bazel(밀폐성·원격 캐시): https://bazel.build/basics — `hermeticity`
- dorny/paths-filter: https://github.com/dorny/paths-filter

## 요약 카드

| 질문 | 답 |
|------|----|
| 모노레포 CI의 본질 질문? | "이 변경이 무엇에 영향을 주는가" (affected) |
| path filter의 맹점? | 의존성 무지 — 공유 lib 변경이 소비자를 안 돌림 (필터 = 그래프의 낡는 사본) |
| 그래프 affected? | 변경 프로젝트 + 역방향 전이 의존자 (Nx/Turbo가 import에서 자동 추출) |
| 캐시 원리? | 태스크 해시(입력) → 출력 재사용 — 19의 BuildKit과 같은 아이디어, 다른 층 |
| Bazel의 자리? | 수천 명·다언어 — 밀폐 강제로 캐시를 "믿을 수 있게" |
| required check 함정? | 스킵 ≠ 통과 ("expected" 무한 대기) → 단일 `ci` 게이트(03)로 |
