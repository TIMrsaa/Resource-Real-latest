# 21 — 공급망 보안: "이 아티팩트를 왜 믿는가"에 답하기

> 파이프라인 전체(01~20)를 관통하던 질문이 하나 있습니다: 03의 액션 SHA 고정, 04의 다이제스트, 18의 dist 재현성, 19의 provenance, 20의 캐시 신뢰 경계 — 전부 "**내가 실행/배포하는 것이 정말 내가 의도한 그것인가**"였습니다. 이 모듈은 그 질문을 체계로 만듭니다: 공격 지도(어디가 뚫리나), SLSA(신뢰의 등급), sigstore/cosign(서명 — 그것도 07의 OIDC로), SBOM(성분표), 그리고 배포 관문에서의 검증까지.

## 학습 목표

1. 공급망 공격 지도를 그립니다 — 소스·의존성·빌드·배포 각 단계의 실제 사고(xz, SolarWinds, codecov)와 함께
2. SLSA Build 레벨(L1~L3)이 각각 어떤 공격을 차단하는지 설명합니다
3. cosign keyless 서명을 이해합니다 — Fulcio(신원 인증서)·Rekor(투명성 로그)·**07의 OIDC**가 어떻게 조립되는지
4. SBOM(syft)을 생성하고 취약점 스캔(grype)을 CI 게이트로 만듭니다
5. 배포 관문(admission)에서 서명·신원을 검증해 "서명 없는 이미지는 클러스터에 못 들어오게" 합니다

## 선행: 03(SHA 고정), 04(다이제스트), 07(OIDC), 18(dist 재현성), 19(provenance) · 도구: docker, cosign, syft/grype, kind, gh
## 비용: 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-sign-and-verify.md](./lab-01-sign-and-verify.md) — keyless 서명, Rekor, provenance 검증
3. [lab-02-sbom-and-admission.md](./lab-02-sbom-and-admission.md) — SBOM·스캔 게이트, admission 검증
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 3h
