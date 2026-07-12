# 이론 — 공격 지도, SLSA, sigstore 해부, SBOM, 배포 관문 검증

> **🌱 17세 눈높이 비유: 급식 재료의 여정**
> - 학교 급식 재료는 농장 → 가공 공장 → 물류 → 급식실을 거칩니다. 어디서든 오염될 수 있습니다
> - **공격 지도** = "농장에서 농약(악성 유지보수자), 공장에서 이물질(빌드 침투), 배송 중 바꿔치기(태그 변경)" — 고리마다 다른 위험
> - **SLSA** = 식품 안전 등급 — "원산지 표시 있음(L1) < 인증 공장에서 가공(L2) < 밀봉·출입 통제 공장(L3)"
> - **cosign 서명** = 밀봉 스티커 — 뜯으면(변조하면) 티가 남
> - **keyless** = 도장 대신 신분증 — "어느 공장(워크플로)이 밀봉했는지"를 신분증(OIDC, 07)으로. 도장은 도둑맞지만 신분증 발급 기록(Rekor)은 공개 장부에 남습니다
> - **SBOM** = 성분표 — 나중에 "그 첨가물이 위험하대!"(신규 CVE) 하면 성분표로 어느 급식이 해당되는지 즉시 조회
> - **admission 검증** = 급식실 문 앞 검사 — 밀봉·성분표 없는 재료는 주방에 못 들어옴

---

## 1. 공격 지도 — 고리별 실제 사고

```
소스 ──▶ 의존성 해석 ──▶ 빌드 ──▶ 아티팩트 ──▶ 배포
 │           │             │          │           │
 xz(2024)    dependency    SolarWinds codecov     서명 없는
 event-      confusion     (2020)     (2021)      이미지 admit
 stream      (2021)                   tj-actions
 (2018)                               (2025)
```

| 고리 | 사고 | 수법 | 배운 것 |
|---|---|---|---|
| 소스 | **xz** | 수년간 신뢰를 쌓은 유지보수자가 백도어 커밋 (테스트 바이너리에 은닉) | 리뷰도 신뢰 기반 — 재현 빌드·최소 의존이 최후 방어 |
| 소스 | event-stream | 지친 관리자가 관리권 이양 → 새 관리자가 악성 배포 | 의존성의 "관리 상태"도 위험 지표 (19의 kaniko 교훈) |
| 의존성 | dependency confusion | 사내 패키지와 같은 이름을 공개 레지스트리에 — 해석기가 공개를 우선 | 레지스트리 우선순위 고정·스코프 예약 |
| 빌드 | **SolarWinds** | 빌드 서버 침투 — **소스는 깨끗**, 빌드 중 주입 | 서명·리뷰로 못 잡음 → 빌드 격리(SLSA L3) |
| CI | codecov | 커버리지 업로더 스크립트 변조 → CI 환경변수(시크릿) 유출 | `curl \| bash` 금지, 체크섬 검증 |
| CI | tj-actions | 인기 액션의 태그를 악성 커밋으로 재지정 (18의 사례) | SHA 고정(03), dist 검증(18) |
| 아티팩트 | 태그 변경 | latest/v1이 다른 이미지를 가리키게 | 다이제스트(04), 서명 검증 |

핵심 통찰: **방어는 고리별로 다릅니다**. 서명은 "빌드 이후 변조"를 잡고, 빌드 격리는 "빌드 중 주입"을 잡고, SBOM은 "이미 배포된 것의 소급 조회"를 잡습니다. 하나로 전부를 막는 도구는 없습니다.

## 2. SLSA — 신뢰의 등급표 (Build Track v1.0)

| 레벨 | 요구 | 차단하는 공격 |
|---|---|---|
| L0 | 없음 | — |
| L1 | **provenance 존재** (어떻게 빌드됐나 기록) | 실수·추적 불가 |
| L2 | 호스티드 빌드 플랫폼이 provenance **서명** | provenance 위조 |
| L3 | 빌드 **격리**(빌드끼리·시크릿 접근 차단), provenance 위조 불가 | **SolarWinds형** (빌드 환경 침투) |

- 19의 `--provenance=true`가 L1의 재료, GHA + slsa-github-generator 또는 GitHub Artifact Attestations가 L3 경로
- SLSA는 "달성"이 아니라 **소비 기준**이기도 합니다: "우리는 L2 미만 아티팩트를 배포하지 않는다"는 정책의 언어

## 3. sigstore 해부 — 키 없는 서명의 구조

고전 서명의 난제: 서명 키의 보관·순환·유출(키가 곧 신뢰의 전부). sigstore는 키를 **10분짜리 신원 인증서**로 대체합니다:

```
cosign sign ghcr.io/org/app@sha256:...
  1. 러너가 OIDC 토큰 획득 ("나는 org/repo의 release.yml, ref=refs/tags/v1.0") ← 07의 그 토큰!
  2. Fulcio(CA): 토큰 검증 → 그 신원이 박힌 단명 인증서 발급 (10분 유효)
  3. cosign: 임시 키로 서명 → 서명+인증서를 레지스트리에 첨부 (이미지 옆 .sig)
  4. Rekor(투명성 로그): 서명 기록을 공개 append-only 로그에 — 사후 부인·은폐 불가
  (임시 키는 즉시 폐기 — 유출될 장기 키가 존재하지 않음)

cosign verify --certificate-identity-regexp='github.com/org/repo/.github/workflows/release.yml.*' \
              --certificate-oidc-issuer=https://token.actions.githubusercontent.com
  = "이 이미지는 'org/repo의 release 워크플로'가 서명했다"를 검증
```

- **검증 대상은 키가 아니라 신원**입니다 — "누가(어느 워크플로가) 서명했나". 07에서 배운 sub 클레임 설계가 그대로 서명 신원 조건이 됩니다
- 인증서가 10분이면 검증은 어떻게? — 서명 **시점**이 Rekor에 기록되므로 "유효 기간 내에 서명됐음"을 사후에도 증명
- 장기 키 방식(cosign generate-key-pair)도 있습니다 — 에어갭 환경 등. 하지만 그 순간 키 관리 문제(22)가 돌아옵니다

## 4. SBOM — 성분표와 그 소비

```
syft ghcr.io/org/app@sha256:... -o spdx-json > sbom.json   # 생성 (SPDX/CycloneDX 형식)
grype sbom:./sbom.json --fail-on high                       # 취약점 대조 + CI 게이트
```

| 관점 | 스캔만 (SBOM 없이) | SBOM 보관 |
|---|---|---|
| 빌드 시점 취약점 | 잡음 | 잡음 |
| **신규 CVE 소급** | 전 이미지 재스캔 (느림·레지스트리 부하) | **저장된 SBOM 조회만** (즉시) |
| 규제·감사 | 불가 | 제출 가능 (미 행정명령 14028 이후 요구 증가) |

SBOM의 진짜 가치는 빌드 시점이 아니라 **그 후**입니다: Log4Shell급 CVE가 터진 날, "우리 프로덕션에서 영향받는 이미지 목록"을 재스캔 없이 분 단위로 뽑는 것. 19의 `--sbom=true`가 이것을 이미지에 첨부했고, ECR 스캔(eks)은 레지스트리 측 보완입니다.

## 5. 배포 관문 — 증명이 게이트가 됩니다

서명·SBOM이 있어도 **검증을 강제하는 관문**이 없으면 장식입니다. 관문의 자리는 admission(k8s 34의 재등장):

```yaml
# Kyverno verifyImages (또는 sigstore policy-controller)
apiVersion: kyverno.io/v1
kind: ClusterPolicy
spec:
  rules:
    - name: require-signed
      match: { any: [{ resources: { kinds: [Pod] } }] }
      verifyImages:
        - imageReferences: ["ghcr.io/org/*"]
          attestors:
            - entries:
                - keyless:
                    subject: "https://github.com/org/repo/.github/workflows/release.yml@*"
                    issuer: "https://token.actions.githubusercontent.com"
```

```
계층 방어 정리:
  CI 게이트     서명·SBOM 생성 + 스캔 통과 못 하면 push 안 함     (생산자 측)
  admission     서명·신원 검증 못 하면 클러스터에 admit 안 함      (소비자 측, 최후)
  런타임        (Falco 등 — 이 커리큘럼 범위 밖, cncf 파트에서)
```

GitOps(14)와 결합하면: 매니페스트는 Git이 진실이고(다이제스트로 고정, 04), 이미지는 admission이 신원을 검증합니다 — **Git의 무결성 + 아티팩트의 무결성**이 함께 닫힙니다.

## 6. 정책의 현실 — 어디까지 강제하나

```
1주차: audit 모드 (위반을 기록만) — 기존 워크로드의 위반 목록 확보
2주차: 신규 네임스페이스만 enforce — 신규부터 규율
그 후: 전체 enforce + 예외는 명시적 exempt 목록 (kube-system, 서드파티...)
★ 처음부터 전체 enforce하면? — 서명 없는 기존 이미지의 재시작이 전부 거절 → 클러스터 마비
```

k8s 34의 VAP 도입 순서(audit→enforce)와 같은 지혜입니다 — 정책은 기술이 아니라 **이행 계획**이 어렵습니다.

## 7. 소스/도구에서 확인하기

- SLSA 명세: https://slsa.dev/spec/v1.0/levels
- sigstore: https://docs.sigstore.dev — cosign/Fulcio/Rekor 아키텍처
- GitHub Artifact Attestations: https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations
- syft/grype: https://github.com/anchore/syft · https://github.com/anchore/grype
- Kyverno verifyImages: https://kyverno.io/docs/policy-types/cluster-policy/verify-images/

## 요약 카드

| 질문 | 답 |
|------|----|
| 공급망의 본질 질문? | "실행/배포되는 것이 검토·의도된 그것과 동일한가" |
| 공격 지도? | 소스(xz)·의존성(confusion)·빌드(SolarWinds)·CI(codecov)·아티팩트(태그) — 고리별 방어가 다름 |
| SLSA L1/L2/L3? | provenance 존재 / 플랫폼 서명 / 빌드 격리(SolarWinds형 차단) |
| keyless 서명? | OIDC 신원(07) → Fulcio 단명 인증서 → Rekor 공개 로그 — 유출될 장기 키가 없음 |
| 검증 대상? | 키가 아니라 **신원** — "어느 저장소의 어느 워크플로가 서명했나" |
| SBOM의 진짜 가치? | 신규 CVE의 **소급 조회** — 재스캔 없이 영향 이미지 목록 |
| 마지막 방어선? | admission 검증(34) — 증명 없는 이미지는 admit 거절, audit→enforce 순서로 |
