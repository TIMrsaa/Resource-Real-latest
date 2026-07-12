# 07 — 지도: 보안 — 공급망부터 런타임까지, 방어의 전 구간

> cicd 21에서 공급망 보안을 "실행되는 것이 의도한 그것인가"로 체계화했다면, 이 지도는 그 질문을 클러스터 전체로 확장한 방어 도구들의 지형입니다. 축은 **소프트웨어 수명주기의 시간선**입니다: 빌드 전(정책·서명 — cosign/in-toto), 배포 시점(admission — OPA/Kyverno), 실행 중(런타임 탐지 — Falco), 그리고 이 모든 것을 관통하는 신원(cert-manager/SPIFFE). cicd 21·22·24에서 만난 도구들(sigstore·OPA·Kyverno)이 여기서 카테고리 지도 위 제자리를 찾습니다.

## 학습 목표

1. 보안을 수명주기 시간선(빌드전/배포시점/런타임 + 관통하는 신원·정책)으로 배치하고 전수 지도를 그립니다
2. 정책 엔진 2강(OPA/Gatekeeper vs Kyverno)의 설계 차이(범용 rego vs K8s 네이티브)를 압니다
3. 신원의 두 축 — 인증서(cert-manager)와 워크로드 아이덴티티(SPIFFE/SPIRE) — 를 구분합니다
4. 런타임 탐지(Falco)가 다른 층(admission)과 무엇이 다른지(예방 vs 탐지) 압니다
5. kind에서 Kyverno admission 정책과 Falco 런타임 탐지를 각각 시식합니다

## 선행: 01(범례), k8s 34(admission), cicd 21(공급망·서명·admission), 22(시크릿), 24(정책) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md) — 지도 본체
2. [lab-01-category-census.md](./lab-01-category-census.md) — 전수 목록·시간선 분류
3. [lab-02-admission-and-runtime.md](./lab-02-admission-and-runtime.md) — Kyverno 예방 + Falco 탐지 시식
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2.5h
