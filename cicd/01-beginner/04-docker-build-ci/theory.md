# 이론 — 레이어 캐시의 규칙, 멀티스테이지, 태그의 계약

> **🌱 17세 눈높이 비유: 도시락 싸기**
> 매일 아침 도시락을 쌉니다. 순서가 이렇습니다: ① 밥 짓기(20분) ② 반찬 만들기(10분) ③ 오늘의 쪽지 넣기(5초)
> - **레이어 캐시** = 어제 한 단계를 그대로 재사용 — 밥이 그대로면 다시 안 짓습니다
> - **캐시 무효화의 규칙** = **한 단계가 바뀌면 그 뒤는 전부 다시 합니다.** 밥을 다시 지으면 반찬도 다시. 순서가 중요한 이유입니다
> - **잘못된 순서** = ①쪽지 ②밥 ③반찬 — 쪽지는 매일 바뀌므로 **매일 밥부터 다시 짓습니다**(30분)
> - **올바른 순서** = 자주 바뀌는 것을 **맨 뒤로** — 밥·반찬은 캐시, 쪽지만 새로(5초)
> - **멀티스테이지** = 부엌(빌드 도구)은 집에 두고 **도시락통만** 학교에 가져갑니다 — 가볍고, 부엌칼을 학교에 안 가져갑니다(보안)
> - **`:latest` 태그** = "오늘 도시락"이라고만 적힌 통 — 어제 것과 구분이 안 돼 뭘 먹었는지(뭘 배포했는지) 아무도 모릅니다

---

## 1. 레이어와 캐시 무효화 — 단 하나의 규칙

Dockerfile의 각 명령은 레이어를 만듭니다. 빌더는 각 단계에서 묻습니다: **"이 명령과 그 입력이 이전과 같은가요?"**

```
같습니다  → 캐시 재사용 (즉시)
다릅니다 → 이 단계 실행 + 이후 모든 단계 무효화 (캐시 연쇄 붕괴)
```

`COPY`/`ADD`는 입력이 **파일 내용**이고, `RUN`은 입력이 **명령 문자열**입니다(내용이 아닙니다 — 그래서 `RUN apt-get update`가 캐시되어 낡은 패키지를 받는 함정이 생깁니다).

### 그래서 순서가 전부입니다

```dockerfile
# ❌ 매 커밋마다 의존성 재설치 (2분)
COPY . .
RUN pip install -r requirements.txt

# ✅ 의존성 파일만 먼저 — 코드가 바뀌어도 캐시 히트 (5초)
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
```

원칙: **변경 빈도가 낮은 것부터 위에.** (베이스 이미지 → 시스템 패키지 → 의존성 매니페스트 → 의존성 설치 → 애플리케이션 코드)

### `.dockerignore` — 보이지 않는 캐시 파괴자

`COPY . .`의 입력에 `.git/`, `node_modules/`, 로그가 포함되면 — 아무 관계 없는 파일 변경이 캐시를 깹니다. 그리고 이미지에 `.git`이 들어가면 **전체 히스토리와 과거의 시크릿**이 배포됩니다.

## 2. 멀티스테이지 — 부엌은 두고 도시락만

```dockerfile
# ── 빌드 스테이지: 컴파일러·헤더·테스트 도구가 여기 삽니다
FROM golang:1.23 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download                    # 의존성 캐시 레이어
COPY . .
RUN CGO_ENABLED=0 go build -o /out/app ./cmd/app

# ── 런타임 스테이지: 바이너리 하나만
FROM gcr.io/distroless/static:nonroot
COPY --from=build /out/app /app
USER nonroot:nonroot
ENTRYPOINT ["/app"]
```

얻는 것 셋:

| | 효과 |
|---|---|
| 크기 | 800MB → 15MB — pull 시간, NAT 전송비(eks 22) |
| 보안 | 셸·패키지 매니저·컴파일러 없음 → 침해 후 공격자의 도구가 없습니다(eks 25 관문 ③) |
| 캐시 | 빌드 스테이지의 의존성 레이어가 별도로 캐시됩니다 |

**베이스 선택 스펙트럼**: `ubuntu`(크고 편함) → `alpine`(작음, musl libc 함정) → `distroless`(셸 없음) → `scratch`(아무것도 없음). 디버깅 편의와 공격 표면의 교환이며, distroless가 대개 균형점입니다(디버그가 필요하면 `:debug` 태그로 임시 교체).

## 3. BuildKit — 현대 빌더

Docker 23+의 기본 빌더. 얻는 것:

- **병렬 실행**: 의존 관계가 없는 스테이지를 동시에
- **캐시 마운트**: 레이어가 아닌 **영속 캐시 디렉터리**
  ```dockerfile
  RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt
  ```
  → 의존성이 하나 추가돼도 나머지는 캐시에서(레이어 캐시는 전부 미스인 상황에서도)
- **시크릿 마운트**: 빌드 시크릿이 레이어에 남지 않습니다
  ```dockerfile
  RUN --mount=type=secret,id=npmrc npm install     # 이미지에 흔적 없음
  ```
  (`ARG`로 시크릿을 넘기면 이미지 히스토리에 **영구히 남습니다** — 고전적 유출)
- **외부 캐시 백엔드**: CI에서 캐시를 저장/복원할 곳

## 4. CI에서의 캐시 — 세 가지 백엔드

러너는 매번 새 VM이므로 캐시를 **어딘가에 내보내고 다시 가져와야** 합니다:

| 백엔드 | 설정 | 특징 |
|--------|------|------|
| **GHA cache** | `cache-from: type=gha` / `cache-to: type=gha,mode=max` | 설정 쉬움, 저장소당 10GB 제한, 7일 미사용 시 삭제 |
| **레지스트리** | `type=registry,ref=<repo>:buildcache` | 무제한, 팀·브랜치 간 공유, 레지스트리 비용 |
| inline | `type=inline` | 이미지에 캐시 메타데이터 포함(단순, mode=max 불가) |

`mode=max`: 중간 레이어까지 전부 캐시(멀티스테이지의 빌드 스테이지 포함). `min`은 최종 이미지 레이어만 — 멀티스테이지에선 대개 무의미합니다.

**캐시 키의 함정**: 브랜치별로 캐시가 분리되면 새 브랜치는 항상 콜드 스타트입니다. `cache-from`에 main 브랜치 캐시를 함께 지정해 폴백을 만듭니다.

## 5. 태그 전략 — 아티팩트 불변성의 계약

```
❌ :latest         움직입니다 — "어떤 커밋인가"에 답할 수 없습니다
❌ :main           같은 문제 (커밋마다 덮어씀)
✅ :git-sha        불변, 커밋과 1:1
✅ :v1.2.3         릴리스 태그 (사람이 읽음)
✅✅ @sha256:...    다이제스트 — **콘텐츠 주소**, 위변조 불가
```

01의 승격 모델이 성립하려면 **배포는 다이제스트로** 참조해야 합니다. 태그는 사람을 위한 별명이고, 태그가 가리키는 곳은 바뀔 수 있습니다(레지스트리에서 재푸시하면). 다이제스트는 내용의 해시라 바뀌지 않습니다.

```yaml
# k8s 매니페스트에서
image: 123.dkr.ecr.ap-northeast-2.amazonaws.com/app@sha256:abc123...   # 배포는 이렇게
```

ECR의 **태그 불변성(tag immutability)** 설정을 켜면 같은 태그 재푸시가 거부됩니다 — 실수로 태그를 움직이는 것을 레지스트리가 막아줍니다.

## 6. 재현 가능한 빌드로 가는 계단

```
1층  lockfile 커밋 (package-lock.json, poetry.lock, go.sum) — 의존성 고정
2층  베이스 이미지를 다이제스트로 고정 (FROM python:3.12@sha256:...)
3층  빌드 인자·타임스탬프 제거 (SOURCE_DATE_EPOCH)
4층  bit-for-bit 재현 — 같은 입력 → 같은 다이제스트 (21의 SLSA가 요구)
```

대부분의 조직은 2층이면 충분합니다. 4층은 공급망 보안이 요구할 때(21).

## 7. 소스/도구에서 확인하기

- BuildKit: https://github.com/moby/buildkit — `frontend/dockerfile/`(Dockerfile 파싱), 캐시 마운트 구현
- docker/build-push-action: https://github.com/docker/build-push-action
- distroless: https://github.com/GoogleContainerTools/distroless
- `docker history <image>` / `dive` — 레이어별 크기와 명령 확인
- ECR 태그 불변성: AWS 문서 "Image tag mutability"

## 요약 카드

| 질문 | 답 |
|------|----|
| 캐시 무효화의 규칙? | 한 단계가 바뀌면 **그 뒤 전부** 무효 — 변경 빈도 낮은 것부터 위로 |
| `COPY . .`의 위치? | 의존성 설치 **뒤**. 그리고 `.dockerignore` 필수 |
| 멀티스테이지가 주는 셋? | 크기(pull·전송비) + 보안(도구 제거) + 캐시 분리 |
| 빌드 시크릿? | `ARG` 금지(히스토리에 영구) → BuildKit `--mount=type=secret` |
| CI 캐시 백엔드? | GHA cache(쉬움) / registry(공유·무제한) — `mode=max` |
| 배포가 참조할 것? | 태그가 아니라 **다이제스트**(@sha256) — 태그는 움직입니다 |
| ECR의 안전장치? | 태그 불변성 설정 |
