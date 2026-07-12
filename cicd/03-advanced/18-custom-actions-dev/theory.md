# 이론 — 액션 3종, JS 액션 해부, 테스트, 배포와 공급망

> **🌱 17세 눈높이 비유: 요리 도구 만들어 팔기**
> - 지금까지 남의 도구를 **사서 썼습니다**(uses:). 이제 **만들어 팝니다**
> - **composite 액션** = 여러 기존 도구를 묶은 세트(칼+도마+집게 묶음) — 06에서 만든 것
> - **Docker 액션** = 아예 새 기계를 만들어 넣기(컨테이너) — 무겁지만 뭐든
> - **JavaScript 액션** = 전자식 도구 — 빠르고 어디서든 작동, 부품(툴킷) 잘 갖춰짐
> - **action.yml** = 도구 설명서(입력/출력/사용법)
> - **번들링** = 도구와 부품(node_modules)을 하나로 포장 — 소비자가 조립 안 하게
> - **공급망 안전** = 내 도구가 안전하다는 보증(성분표, 최소 권한, 투명한 소스)

---

## 1. 액션 3종 — 선택 기준

| | composite | Docker | JavaScript |
|---|---|---|---|
| 형태 | 스텝 묶음(YAML) | Dockerfile | Node 코드 |
| 실행 | 호출 잡의 러너 | 컨테이너 | Node 런타임 |
| 시작 속도 | 빠름 | 느림(이미지 pull) | 빠름 |
| 플랫폼 | 러너 의존 | Linux(주로) | 크로스플랫폼 |
| 로직/상태/API | 제한적(셸) | 자유 | 자유(JS 생태계) |
| 툴킷 | — | 임의 언어 | @actions/* 풍부 |
| 자리 | 셸 명령 조합(06) | 특수 도구·언어 | **로직·API·상태** |

선택: 셸 조합이면 composite(06), 특정 언어·도구면 Docker, **로직/API/크로스플랫폼이면 JavaScript**(이 모듈). 마켓플레이스의 주류가 JS인 이유는 빠르고 어디서든 돌기 때문.

## 2. JavaScript 액션 해부

```
my-action/
├── action.yml          ← 메타데이터(입력/출력/실행 방법)
├── src/index.js        ← 로직
├── dist/index.js       ← 번들(node_modules 포함, 커밋됨)
├── package.json
└── README.md
```

### action.yml — 계약

```yaml
name: 'My Action'
description: '무엇을 하는가'
inputs:
  who:
    description: '인사 대상'
    required: false
    default: 'world'
outputs:
  greeting:
    description: '생성된 인사말'
runs:
  using: 'node20'
  main: 'dist/index.js'     # ★ 번들된 것을 가리킴
```

### index.js — 툴킷 사용

```javascript
const core = require('@actions/core');
const github = require('@actions/github');

try {
  const who = core.getInput('who');           // 입력 (03의 인젝션 방어: core가 안전 처리)
  const greeting = `Hello, ${who}`;
  core.setOutput('greeting', greeting);        // 출력 (steps.x.outputs.greeting)
  core.info(`context: ${github.context.eventName}`);  // github 컨텍스트
  if (!who) core.setFailed('who is required'); // 실패 처리 (exit code)
} catch (e) {
  core.setFailed(e.message);
}
```

- `@actions/core`: 입력/출력/로깅/시크릿 마스킹/상태 — **입력 처리가 안전**(03의 인젝션을 툴킷이 방어)
- `@actions/github`: 이벤트 컨텍스트, Octokit(API 클라이언트)
- `core.setSecret(x)`: 값을 로그에서 마스킹(생산자가 시크릿 노출 방지)

## 3. 번들링 — 왜 dist를 커밋하나

```
문제: 액션이 node_modules에 의존 → 소비자가 npm install 해야?
해결: ncc로 단일 파일로 번들 → dist/index.js 하나에 모든 의존성
      → 소비자는 uses: 만 하면 됨 (설치 불필요)
```

```bash
npm install -g @vercel/ncc
ncc build src/index.js -o dist
# dist/index.js를 커밋 (action.yml의 main이 이것을 가리킴)
```

**번들을 커밋하는 것이 액션의 관례**입니다 — 소비자의 러너가 npm install 없이 바로 실행하게. 단 이것이 공급망 관점의 함정도 됩니다(dist가 src와 다를 수 있음 — §5).

## 4. 테스트 — 05의 원리 적용

```javascript
// 액션 로직을 순수 함수로 분리 → 단위 테스트 (05의 Fake/의존성 주입)
// src/greet.js
function greet(who) {
  if (!who) throw new Error('who is required');
  return `Hello, ${who}`;
}
module.exports = { greet };

// __tests__/greet.test.js
const { greet } = require('../src/greet');
test('greets', () => expect(greet('world')).toBe('Hello, world'));
test('rejects empty', () => expect(() => greet('')).toThrow());
```

- **로직을 툴킷에서 분리**해 단위 테스트(05의 아이스크림 콘 회피 — 의존성 주입)
- 통합 테스트: 실제 워크플로에서 액션을 `uses: ./`로 호출
- @actions/core를 모킹하거나, 로직 함수를 분리해 순수하게 유지

## 5. 배포와 버전 관리 — 소비자의 안전

```
릴리스 태그: v1.0.0 (semver)
이동 태그:   v1 (major만 — 소비자가 uses: action@v1 로 자동 패치)
SHA:         특정 커밋 (소비자가 고정하면 불변 — 03의 규율)
```

생산자의 책임(03 pitfall 4의 반대편):

```
- v1 이동 태그를 제공하되, 그것이 "움직인다"는 것을 소비자가 알게
- 보안 감사가 된 릴리스만 태그
- dist가 src에서 재현 가능하게 (빌드 검증 — 소비자가 dist를 신뢰)
- 최소 권한: 액션이 요구하는 permissions를 문서화
```

마켓플레이스 배포: 릴리스 생성 시 "Publish to Marketplace" — action.yml의 name/description/branding이 목록에 표시.

## 6. 공급망 관점 — 좋은 액션의 조건

내 액션을 쓰는 사람에게 나는 공급망의 일부입니다(03의 위험을 생산자가 책임):

```
투명성: 소스가 공개, dist가 src에서 재현 가능
최소 권한: 필요한 permissions만 요구, 문서화
입력 검증: 인젝션·악용 방어 (@actions/core가 도움)
시크릿 취급: core.setSecret으로 마스킹, 로그 노출 방지
버전: SHA 고정 가능하게, 이동 태그의 의미 명시
의존성: node_modules 취약점 스캔 (dist에 번들되므로 그것도 코드)
```

21(공급망 보안)에서 소비자 관점(서명 검증, SBOM)을 다루지만, 여기서는 **생산자로서** 그 신뢰를 만드는 법.

## 7. 소스/도구에서 확인하기

- 액션 개발: https://docs.github.com/actions/creating-actions
- @actions/toolkit: https://github.com/actions/toolkit
- @vercel/ncc(번들러): https://github.com/vercel/ncc
- actions/runner(액션이 실행되는 러너 — 27 기여): https://github.com/actions/runner

## 요약 카드

| 질문 | 답 |
|------|----|
| 액션 3종? | composite(스텝) / Docker(임의 도구) / JavaScript(로직·API) |
| JS 액션 구조? | action.yml(계약) + dist/index.js(번들) |
| 왜 dist 커밋? | 소비자가 npm install 없이 실행 (ncc 번들) |
| 테스트? | 로직을 툴킷에서 분리 → 순수 함수 단위 테스트(05) |
| 버전? | semver + 이동 태그(v1) + SHA 고정 가능(03) |
| 생산자 책임? | 투명성·최소권한·입력검증·시크릿마스킹 (03의 반대편) |
