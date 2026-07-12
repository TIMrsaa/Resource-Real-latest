# 42 — 코드베이스 투어: 지도를 손에 넣습니다

> 수만 개의 Go 파일에서 길을 잃지 않는 법. 컴포넌트별 진입점에서 핵심 루프까지 **코드 읽기 원정** 4개를 떠납니다 — 모듈 21~28에서 배운 동작 원리가 코드 위에서 그대로 보입니다.

## 학습 목표

1. 컴포넌트별 "진입점 → 본체" 경로를 직접 따라갑니다
2. 코드 읽기 전술(grep 입구, 인터페이스 추적, 테스트로 이해)을 익힙니다
3. 원정 4개: kubectl 명령 한 개 / 스케줄러 사이클 / Deployment 컨트롤러 / API 서버 등록
4. "어느 SIG가 이 코드의 주인인가"를 알아내는 법 (43으로 연결)

## 선행: 모듈 41(빌드된 리포), 21/24/25(동작 이론) · 환경: 로컬 (에디터 + 클론 리포)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-kubectl-to-apiserver.md](./lab-01-kubectl-to-apiserver.md) — 원정 ①②
3. [lab-02-controllers-scheduler.md](./lab-02-controllers-scheduler.md) — 원정 ③④
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) (cleanup 불필요 — 읽기만 합니다)

소요: 이론 1h + 원정 3h
