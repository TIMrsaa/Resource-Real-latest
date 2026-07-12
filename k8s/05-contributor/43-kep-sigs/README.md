# 43 — KEP과 SIG: Kubernetes는 누가 어떻게 결정하는가

> 코드(41~42) 다음은 **사람과 절차**입니다. SIG 구조, KEP 프로세스, 커뮤니케이션 채널 — 기술이 아니라 이걸 몰라서 첫 기여가 막히는 경우가 더 많습니다. lab은 "실제 KEP 한 편 정독"과 "커뮤니티 입주 절차"다.

## 학습 목표

1. SIG/WG 구조와 "모든 코드에는 주인 SIG가 있다"를 체화합니다
2. KEP의 구조(동기/설계/단계 기준)를 읽고, 기능의 역사를 추적합니다
3. 기능 단계(Alpha→Beta→GA)가 KEP과 어떻게 묶이는지 압니다 (모듈 29와 연결)
4. 커뮤니티 채널(Slack/메일링리스트/회의)에 실제로 입주합니다
5. CLA 서명 등 기여 전 행정 절차를 마칩니다 (45의 선행 조건)

## 선행: 모듈 42(OWNERS에서 SIG를 봤습니다), 29(feature gate) · 환경: 브라우저 + GitHub 계정

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-kep-archaeology.md](./lab-01-kep-archaeology.md) — KEP 고고학: 기능 하나의 일대기
3. [lab-02-community-onboarding.md](./lab-02-community-onboarding.md) — 커뮤니티 입주 + CLA
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) (cleanup 불필요)

소요: 이론 1.5h + 실습 2h
