# 07 — OIDC: CI에서 장기 자격증명을 없애입니다

> 04에서 우리는 AWS 액세스 키를 GitHub 시크릿에 넣고 "07에서 없앨 부채"라고 적었습니다. 이 모듈이 그것을 갚습니다. 원리는 eks 09에서 이미 봤습니다 — **IRSA가 Pod에게 했던 일을, OIDC가 워크플로에게 합니다**: 신뢰할 수 있는 발급자가 서명한 단명 토큰을 STS가 IAM 역할로 교환해줍니다. 저장할 비밀이 없으면 유출될 비밀도 없습니다.

## 학습 목표

1. OIDC 신뢰 흐름 4단계를 그립니다 — GitHub이 발급, AWS가 검증, STS가 교환
2. IAM에 OIDC 제공자와 역할을 만들고, **신뢰 정책의 조건(`sub`)** 을 정확히 좁힙니다
3. 04의 빌드 워크플로에서 장기 키를 제거하고 OIDC로 전환합니다
4. 조건 설계의 함정을 압니다 — 와일드카드 `sub`가 만드는 조직 전체 침해 경로
5. environment(06)와 결합해 "프로덕션 역할은 승인된 배포에서만" 을 만듭니다

## 선행: eks 09(IRSA/OIDC — 같은 원리), 04(빌드 워크플로), 06(environments) · 도구: gh, AWS CLI
## 비용: 없음 (IAM·STS 무료). ECR 저장 소량

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-oidc-setup.md](./lab-01-oidc-setup.md) — 제공자·역할·신뢰 정책, 첫 assume-role
3. [lab-02-scope-and-environments.md](./lab-02-scope-and-environments.md) — 조건 좁히기, 침해 실험, 환경별 역할
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
