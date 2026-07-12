# 12 — AWS 네이티브 관측성: Container Insights와 로그 파이프라인

> 중급 졸업 모듈. "보인다"를 AWS 도구로 구축합니다 — Container Insights(메트릭), Fluent Bit(로그), CloudWatch 알람, 그리고 **관측성 비용**이라는 복병까지. (Prometheus/Grafana 생태계는 cncf 파트에서 — 여기선 AWS 네이티브 축)

## 학습 목표

1. 관측성 3축(메트릭/로그/트레이스)과 EKS에서의 AWS 네이티브 구성을 그립니다
2. amazon-cloudwatch-observability 애드온으로 Container Insights를 켭니다
3. 로그 파이프라인(컨테이너 stdout → Fluent Bit → CloudWatch Logs)을 검증합니다
4. Logs Insights 쿼리와 메트릭 알람으로 "장애 전에 아는" 장치를 만듭니다
5. 관측성 비용 구조(수집량 과금!)와 통제 수단을 압니다

## 선행: k8s 14(probe)/38(진단 루틴), eks 09(애드온 권한)/11(애드온) · 환경: 공유 EKS (⚠️ CloudWatch 수집 과금)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-container-insights.md](./lab-01-container-insights.md) — 애드온 활성화, 메트릭/로그 확인
3. [lab-02-queries-alarms.md](./lab-02-queries-alarms.md) — Logs Insights, 알람, 비용 통제
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh` (★ 수집 중지)

소요: 이론 1h + 실습 2h
