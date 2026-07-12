# 03 — 콘솔과 CloudShell: 터미널 밖의 운영 도구

> EKS 콘솔은 "구경거리"가 아닙니다 — 리소스 뷰가 동작하는 원리(콘솔도 access entry를 따르는 클라이언트일 뿐), CloudShell이라는 "어디서나 터미널", 그리고 **콘솔/CLI/kubectl의 역할 분담**을 정리합니다.

## 학습 목표

1. EKS 콘솔의 구조(리소스/컴퓨팅/네트워킹/애드온/액세스/관측)를 손에 익힙니다
2. 콘솔 리소스 뷰의 동작 원리와 "권한 없음" 오류의 정체를 압니다 (모듈 02의 응용)
3. CloudShell에서 kubectl 환경을 1분 만에 구성합니다 (출장지/타인 PC 시나리오)
4. "이 작업은 콘솔/CLI/kubectl 중 무엇으로?"의 기준을 세웁니다

## 선행: 모듈 01, 02 (access entries) · 환경: 공유 EKS + 브라우저

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-console-tour.md](./lab-01-console-tour.md) — 콘솔 6개 탭 투어 + 권한 수수께끼
3. [lab-02-cloudshell.md](./lab-02-cloudshell.md) — CloudShell 셋업과 비상 운영 시나리오
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) (cleanup: lab 중 생성물 없음)

소요: 이론 0.5h + 실습 1h
