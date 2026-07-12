# 13 — CloudWatch와 Container Insights: AWS 관측의 기본기와 요금의 물리

> advanced 트랙의 시작 — 지금까지 지은 오픈소스 스택(06~12)과 같은 그림을 **AWS 관리형 부품**으로 다시 그립니다. 그 첫 부품이 CloudWatch입니다: EKS의 컨트롤 플레인 로깅(05의 audit이 여기로!), Container Insights(Fluent Bit + CloudWatch agent가 EKS 애드온으로 — 06의 지식이 그대로), Logs Insights 쿼리(02의 구조화가 여기서도 보상), 메트릭·알람. 그리고 이 모듈의 가장 실무적인 주제 — **CloudWatch 요금의 물리**: ingest(수집)가 비싸고 저장은 상대적으로 싸다는 구조가 모든 설계 판단(무엇을 CW로, 무엇을 S3로)을 지배합니다. eks 파트의 클러스터를 재사용하며, 비용 가드레일을 지킵니다.

## 학습 목표

1. EKS 컨트롤 플레인 로깅 5종(api·audit·authenticator·controllerManager·scheduler)을 켜고 읽습니다
2. Container Insights의 구조(애드온 = Fluent Bit + CW agent)를 06의 지식으로 해부합니다
3. Logs Insights 쿼리 문법으로 구조화 로그를 조사합니다 (02·12의 LogQL과 대응)
4. CloudWatch 요금 구조(ingest 중심)를 이해하고 설계 판단(필터·계층화)에 적용합니다
5. CW 메트릭·알람과 Prometheus 세계(08~10)의 대응 관계를 정리합니다

## 선행: 06(Fluent Bit — 필수), 05(audit), eks 파트(클러스터·비용 가드레일) · 도구: AWS 계정, eksctl/기존 EKS, aws cli
## 비용: ⚠️ 발생 — CloudWatch ingest·저장·쿼리, EKS 클러스터. 실습 후 cleanup.sh 필수. 로그 그룹 보존 설정 확인

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-control-plane-and-insights.md](./lab-01-control-plane-and-insights.md) — 컨트롤 플레인 로깅·Container Insights
3. [lab-02-logs-insights-and-cost.md](./lab-02-logs-insights-and-cost.md) — Logs Insights 쿼리·요금 통제
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2h
