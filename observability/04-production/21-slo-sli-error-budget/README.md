# 21 — SLI·SLO·에러 버짓: 신뢰성을 숫자로 계약합니다

> production 트랙의 시작. 지금까지 신호를 모으고(01~12) 관리형으로 옮기고(13~18) 심화했습니다(19~20) — 이제 그 위에서 **"얼마나 안정적이어야 하는가"를 숫자로 정하는 규율**을 세웁니다. SLI(무엇을 잴 것인가 — 사용자 관점의 지표), SLO(목표 — 예: 30일간 99.9%), 에러 버짓(100%가 아니어도 되는 만큼의 실패 허용량 — 혁신의 예산), 그리고 이 파트 알림 규율(10)의 정점인 **멀티윈도우 번레이트 알림**("얼마나 급하게 버짓을 태우고 있는가"로 울립니다)을 recording rules(08) 위에 구현합니다. SLO는 기술이 절반, 조직이 절반입니다 — "버짓 소진 시 릴리즈를 멈춘다"는 합의가 없으면 숫자는 장식입니다.

## 학습 목표

1. SLI 고르기(사용자 관점·측정 지점)와 SLO 정하기(과거 데이터 기반)를 수행합니다
2. 에러 버짓의 계산과 의미(혁신 vs 안정의 예산 협상)를 압니다
3. 번레이트의 개념과 멀티윈도우 알림(빠른 소진=page, 느린 소진=ticket)을 구현합니다
4. SLO 대시보드(버짓 잔량·소진 추세)를 만듭니다
5. SLO의 조직 계약(버짓 정책·릴리즈 게이트)과 흔한 실패를 압니다

## 선행: 08(recording rules — 필수), 10(알림 규율), 03(histogram·버킷) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-sli-slo-rules.md](./lab-01-sli-slo-rules.md) — SLI 정의→SLO recording rules→버짓 계산
3. [lab-02-burn-rate-alerts.md](./lab-02-burn-rate-alerts.md) — 멀티윈도우 번레이트 알림 구현·검증
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2h
