# 이론 — LLB와 솔버, 캐시의 실체, 멀티아치, Dockerfile 너머

> **🌱 17세 눈높이 비유: 레고 조립 공장**
> - **Dockerfile** = 조립 설명서 (사람이 읽는 언어)
> - **frontend** = 설명서를 "조립 단계 그래프"로 번역하는 설계사 — 어떤 단계가 어떤 단계에 의존하는지 화살표로
> - **LLB** = 그 그래프 자체. 각 단계에 "부품 지문"(해시)이 붙어 있습니다
> - **solver(솔버)** = 공장장 — 그래프를 보고 "이 부분은 지난번에 조립한 것과 부품 지문이 같네? 창고(캐시)에서 꺼내", "이 두 부분은 서로 독립이네? 동시에 조립해"
> - **캐시 익스포트** = 창고를 다른 공장(ephemeral 러너)과 공유 — 창고 없는 새 공장도 처음부터 다시 안 만듦
> - **멀티아치** = 같은 설명서로 왼손잡이용(arm64)/오른손잡이용(amd64) 제품을 둘 다 생산
> - **manifest list** = 매장 점원 — 손님(노드)이 오면 손잡이 방향을 보고 맞는 제품을 자동으로 건넴

---

## 1. 레거시 빌더 → BuildKit: 무엇이 바뀌었나

docker build는 18.09부터 BuildKit이 기본 엔진입니다(레거시 빌더는 순차 실행·단순 캐시). 차이는 곧 04에서 배운 기능들의 출처입니다:

| | 레거시 빌더 | BuildKit |
|---|---|---|
| 실행 | Dockerfile 위→아래 순차 | **DAG 병렬** (독립 스테이지 동시) |
| 캐시 | 로컬, 명령 문자열 비교 | **콘텐츠 주소 기반** + 원격 익스포트 |
| 컨텍스트 전송 | 전부 업로드 | 필요한 파일만 (lazy) |
| 시크릿 | 없음 (ARG 유출 사고) | `--mount=type=secret` (04) |
| 캐시 마운트 | 없음 | `--mount=type=cache` (04) |
| 멀티 플랫폼 | 불가 | `--platform` 동시 빌드 |
| 증명서 | 없음 | provenance/SBOM attestation (21) |

04에서 쓴 `--mount=type=cache/secret`이 모두 BuildKit 기능이었습니다 — 이 모듈은 그것들이 **어떻게** 가능한지를 봅니다.

## 2. 아키텍처 — frontend → LLB → solver → worker

```
Dockerfile ──(frontend: dockerfile.v0)──▶ LLB(빌드 그래프) ──▶ solver ──▶ worker(실행)
                                              │                  │
HLB/Earthfile 등 ──(다른 frontend)──────────▶ 같은 LLB          캐시 판정: 각 정점의
                                                                 digest가 캐시에 있나요?
```

- **frontend**: Dockerfile을 LLB로 컴파일하는 번역기. `# syntax=docker/dockerfile:1.7` 첫 줄이 frontend 버전 지정입니다 — **frontend 자체가 이미지로 배포**되어, 데몬 업그레이드 없이 새 Dockerfile 문법을 씁니다
- **LLB (Low-Level Build)**: 콘텐츠 주소 기반 DAG. 각 정점(vertex)은 연산(소스 pull, exec, 파일 복사)이고, 정점의 digest는 "연산 내용 + 모든 입력의 digest"로 계산됩니다
- **solver**: LLB를 받아 정점별로 캐시 히트를 판정하고, 미스인 정점만 worker에서 실행. **의존 관계 없는 정점은 병렬 실행**
- **worker**: 실제 실행 환경 (containerd/OCI). buildx의 driver가 이 worker의 위치를 정합니다

### 이것이 04의 규칙을 설명합니다

```
캐시 키(정점 digest) = 연산 정의 + 입력들의 digest
  ├─ COPY의 입력 digest = 복사되는 파일들의 내용 해시
  │    → 파일 내용이 같으면 mtime이 달라도 히트 (내용 기반!)
  └─ RUN의 입력 = 명령 문자열 + 부모 정점 digest
       → 부모가 바뀌면 연쇄 미스 ("자주 바뀌는 것을 아래로"의 이유)
```

04의 규칙 "COPY package.json → npm install → COPY . ."이 성립하는 이유가 여기 있습니다: package.json의 내용 digest가 안 변하면 npm install 정점이 히트합니다.

## 3. buildx와 driver — 빌더가 어디서 도나

`docker buildx`는 BuildKit의 CLI 프론트입니다. **driver**가 buildkitd의 위치를 정합니다:

| driver | buildkitd 위치 | 멀티아치 | 캐시 익스포트 | 자리 |
|---|---|---|---|---|
| docker (기본) | 도커 데몬 내장 | 제한적 | 제한적(inline만) | 로컬 단순 빌드 |
| **docker-container** | 컨테이너로 별도 실행 | ✅ | ✅ 전부 | **CI 표준** |
| kubernetes | K8s Pod들 | ✅ (아치별 Pod) | ✅ | 대규모 빌드팜 |
| remote | 원격 buildkitd | ✅ | ✅ | 공유 빌드 서버 |

기본 docker driver로는 `--platform` 다중 지정과 registry 캐시 익스포트가 안 됩니다 — CI에서 `docker buildx create`(docker-container driver)가 사실상 첫 줄인 이유.

## 4. 캐시 익스포트 — ephemeral 러너의 창고 문제

08에서 배웠듯 CI 러너는 매번 새것(ephemeral)입니다 — 로컬 캐시가 없습니다. 해법은 캐시를 밖에 저장:

| type | 저장 위치 | 특징 |
|---|---|---|
| `inline` | 이미지 자체에 메타데이터 | 설정 최소, **min만 가능** |
| `registry` | 별도 캐시 이미지 | min/max 선택, 표준 |
| `gha` | GitHub Actions 캐시 | GHA 전용, 10GB 한도 |
| `s3` | S3 버킷 | 자체 러너(08)에서 유용 |

```bash
docker buildx build \
  --cache-to   type=registry,ref=repo/app:cache,mode=max \
  --cache-from type=registry,ref=repo/app:cache .
```

**min vs max**: min은 최종 스테이지의 레이어만, **max는 중간 스테이지 전부** 익스포트. 멀티스테이지(04)에서 min을 쓰면 빌드 스테이지 캐시가 통째로 빠져 "캐시를 붙였는데 안 먹는" 대표 함정이 됩니다.

## 5. 멀티아치 — 세 가지 생산 방법

eks 19에서 본 `exec format error`의 반대편. amd64 러너에서 arm64 이미지를 만드는 방법:

| 방법 | 원리 | 속도 | 조건 |
|---|---|---|---|
| **QEMU 에뮬레이션** | binfmt_misc로 arm64 바이너리를 명령어 단위 번역 | **5~20배 느림** | 설정만 하면 됨 |
| **크로스 컴파일** | 빌드는 내 아치에서, 산출물만 타깃 아치로 | 네이티브급 | 언어가 지원해야 (Go/Rust 우수) |
| **네이티브 러너** | arm64 러너에서 직접 빌드 (GHA `ubuntu-24.04-arm`, 08의 ARC+Graviton) | 네이티브 | 러너 준비 필요 |

크로스 컴파일의 핵심 문법 — 빌드 스테이지는 **빌드 머신 아치**로 돌리고 산출물만 타깃으로:

```dockerfile
FROM --platform=$BUILDPLATFORM golang:1.23 AS build   # 빌드는 러너 아치에서 (에뮬레이션 없음!)
ARG TARGETOS TARGETARCH
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o /app .
FROM gcr.io/distroless/static                          # 최종 스테이지만 타깃 아치
COPY --from=build /app /app
```

### manifest list (OCI image index) — 소비자가 자동으로 받는 원리

```
repo/app:v1  ──▶  image index (manifest list)
                    ├─ manifest (linux/amd64) ──▶ config + layers
                    └─ manifest (linux/arm64) ──▶ config + layers
노드의 containerd: "나는 arm64" → index에서 arm64 manifest를 골라 pull
```

태그 하나가 실제로는 **아치별 manifest의 목록**을 가리킵니다. eks 19의 `exec format error`는 이 index가 없거나(단일 아치 이미지) 노드 아치의 manifest가 빠졌을 때입니다. `--platform linux/amd64,linux/arm64 --push`가 index까지 만들어 push합니다 (다이제스트 고정 시 **index의 digest**를 고정해야 두 아치 모두 커버 — 04).

## 6. Dockerfile 너머 — 도구 지형

모두 같은 것(OCI 이미지)을 만듭니다. 차이는 "무엇으로부터, 어떤 권한으로":

| | BuildKit | ko | buildpacks (CNB) | kaniko |
|---|---|---|---|---|
| 입력 | Dockerfile | **Go 소스** (Dockerfile 없음) | 소스 자동 감지 | Dockerfile |
| 데몬 | buildkitd | **없음** | 도커 데몬 | 없음 |
| 특권 | rootless 가능 | 불필요 | 데몬 의존 | 불필요 (K8s 안 유명) |
| 캐시 | 강력 (§4) | Go 빌드 캐시 | 레이어 재사용 | registry 캐시 |
| 상태 | 표준 | Go 생태계 표준 | 표준화 조직에 강점 | **2025 아카이브** ⚠️ |

- **ko**: `ko build ./cmd/app` 한 줄 — Go 바이너리를 base 이미지에 얹어 push까지. Tekton(16)·Knative 자체가 ko로 빌드됩니다. 재현성이 높아 공급망(21)에서도 유리
- **buildpacks**: `pack build myapp` — 소스를 감지(detect)해 빌드. 킬러 기능은 **rebase**: 앱 레이어는 그대로 두고 베이스 이미지 레이어만 교체 — 재빌드 없이 OS 패치. 수백 서비스의 베이스 일괄 패치가 초 단위
- **kaniko**: "K8s 안에서 privileged 없이 Dockerfile 빌드"로 오래 표준이었으나 **2025년 저장소 아카이브**(유지보수 종료). 기존 사용처는 BuildKit rootless나 원격 buildkitd로 이전이 과제입니다

### rootless — K8s 러너에서 빌드하는 문제 (08의 후속)

```
문제: docker build는 데몬 필요 → K8s Pod 러너에는 데몬이 없음
  ① DinD(privileged) — 노드 장악 가능한 특권 (08에서 금지한 것)
  ② kaniko — 아카이브됨
  ③ BuildKit rootless — buildkitd를 비특권 컨테이너로 ← 현재 표준 경로
  ④ 원격 buildkitd — 빌드 전용 서버/풀에 위임 (driver=remote)
```

## 7. attestation — 빌드가 증명서를 첨부합니다 (21의 예고)

```bash
docker buildx build --provenance=true --sbom=true --push -t repo/app:v1 .
# image index에 이미지 manifest와 나란히 attestation manifest가 붙음
#   provenance: 어떤 소스·빌더·파라미터로 만들어졌나 (SLSA)
#   SBOM: 무엇이 들어있나 (패키지 목록)
```

18에서 "dist가 src에서 나온 것"을 verify-dist로 증명했듯, provenance는 "이미지가 이 소스·이 빌더에서 나온 것"의 증명입니다. 검증(소비자 관점)은 21에서.

## 8. 소스/도구에서 확인하기

- BuildKit(LLB·frontend 소개 포함): https://github.com/moby/buildkit — `docs/`와 `frontend/dockerfile/docs/reference.md`
- buildx driver: https://docs.docker.com/build/builders/drivers/
- 멀티 플랫폼: https://docs.docker.com/build/building/multi-platform/
- ko: https://ko.build / buildpacks: https://buildpacks.io
- kaniko 아카이브 공지: https://github.com/GoogleContainerTools/kaniko (README 상단)

## 요약 카드

| 질문 | 답 |
|------|----|
| BuildKit 파이프? | frontend → LLB(콘텐츠 주소 DAG) → solver(캐시 판정·병렬) → worker |
| 04 규칙의 원리? | 캐시 키 = 연산 + 입력 digest → 부모 변경은 연쇄 미스 |
| CI 캐시? | ephemeral 러너라 익스포트 필수 — registry/gha, 멀티스테이지는 **mode=max** |
| 멀티아치 3법? | QEMU(느림) / 크로스 컴파일($BUILDPLATFORM) / 네이티브 러너 |
| manifest list? | 태그 → 아치별 manifest 목록 — 노드가 자기 아치를 골라 pull (eks 19) |
| Dockerfile 너머? | ko(Go·데몬 없음), buildpacks(rebase), kaniko(아카이브 ⚠️), rootless가 표준 경로 |
