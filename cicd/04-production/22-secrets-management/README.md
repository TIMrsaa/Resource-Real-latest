# 22 — 시크릿 관리: 최고의 시크릿은 존재하지 않는 시크릿

> 07에서 장기 AWS 키를 OIDC로 없앴고, 21에서 서명 키를 keyless로 없앴습니다 — 이 모듈은 그 원칙("시크릿을 지키는 최선은 없애는 것")을 체계로 만들고, **없앨 수 없는 시크릿**(서드파티 API 키, DB 자격증명)을 다루는 도구들 — Vault의 동적 시크릿, 그리고 GitOps(14)의 난제 "Git이 진실인데 시크릿은 Git에 못 넣는다"를 푸는 세 가지(sealed-secrets/SOPS/External Secrets) — 를 비교·실습합니다.

## 학습 목표

1. 시크릿을 "수명(정적/동적) × 보관(플랫폼/스토어/Git)"의 2축으로 분류하고, 각 시크릿에 "없앨 수 있는가"를 먼저 묻습니다
2. CI 플랫폼 시크릿(GHA)의 실체 — 마스킹의 한계(03), fork PR 규칙, environment 승인(06) — 를 압니다
3. Vault의 동적 시크릿(TTL 자격증명)이 "유출돼도 이미 만료"를 어떻게 구현하는지 이해합니다
4. GitOps 시크릿 3해법(sealed-secrets/SOPS/External Secrets Operator)의 구조와 결정 기준을 압니다
5. 유출 대응(스캔·순환·전파)을 절차로 만듭니다 — CircleCI 2023이 왜 "전 고객 순환"이었는지

## 선행: 03(마스킹 한계), 07(OIDC), 14(GitOps), 21(keyless) · 도구: kind, kubectl, gitleaks, kubeseal, sops+age, gh
## 비용: 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-eliminate-and-scan.md](./lab-01-eliminate-and-scan.md) — 시크릿 감사·스캔 게이트·제거 우선순위
3. [lab-02-gitops-secrets.md](./lab-02-gitops-secrets.md) — sealed-secrets vs SOPS vs ESO 삼자 비교
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2.5h
