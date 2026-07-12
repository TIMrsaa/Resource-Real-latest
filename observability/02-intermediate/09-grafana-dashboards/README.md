# 09 — Grafana 대시보드: 그래프 벽이 아니라 조사 동선

> 08에서 메트릭이 쌓이기 시작했습니다. 이제 그것을 **사람이 쓰는 화면**으로 만듭니다 — 단, 목표는 "예쁜 그래프 벽"이 아니라 **장애의 순간에 실제로 쓰이는 조사 동선**입니다(01의 함정 3). 이 모듈은 대시보드 설계 방법론(USE — 리소스의 관점, RED — 서비스의 관점), Grafana의 구조(데이터소스·패널·변수), 드릴다운 설계(전체→서비스→Pod로 좁히는 계층), 그리고 **대시보드 as code**(JSON·프로비저닝·GitOps — 클릭으로 만든 대시보드는 낡습니다)를 다룹니다. 여기서 만든 대시보드 계층이 10(알림의 착지점)·23(장애 대응 동선)의 무대가 됩니다.

## 학습 목표

1. USE(리소스)와 RED(서비스) 방법론으로 "무엇을 보여줄지"를 설계합니다
2. 변수(templating)로 하나의 대시보드가 모든 서비스·네임스페이스를 커버하게 합니다
3. 드릴다운 계층(개요→서비스→인스턴스)과 링크로 조사 동선을 만듭니다
4. 대시보드를 코드로(JSON·ConfigMap 프로비저닝·GitOps) 관리합니다
5. 대시보드 안티패턴(그래프 벽·평균의 함정·무맥락 숫자)을 피합니다

## 선행: 08(데이터 공급 — 필수), 03(분위수·rate) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-red-dashboard.md](./lab-01-red-dashboard.md) — RED 서비스 대시보드를 변수·드릴다운으로
3. [lab-02-dashboards-as-code.md](./lab-02-dashboards-as-code.md) — 프로비저닝·GitOps 관리
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
