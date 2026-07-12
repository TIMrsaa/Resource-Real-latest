# 16 — ADOT: 하나의 Collector로 AMP·CloudWatch·X-Ray 전부

> AWS Distro for OpenTelemetry(ADOT)는 11에서 배운 OTel Collector의 **AWS 배포판**입니다 — 같은 파이프라인 문법(receiver→processor→exporter)에 AWS exporter들(awsxray·awsemf·prometheusremotewrite+SigV4)과 AWS의 검증·지원이 더해진 것. EKS 애드온으로 설치되고 IRSA로 인증합니다(14의 패턴). 이 모듈의 핵심 그림은 **"수집 한 번, 목적지 셋"** — 앱은 OTLP로 한 번만 내보내고, ADOT가 메트릭은 AMP로, 트레이스는 X-Ray로, (선택) 메트릭·로그는 CloudWatch로 분배합니다. 11의 지식이 그대로 통하는 것을 확인하며, AWS 관측 스택의 수집층을 완성합니다.

## 학습 목표

1. ADOT = OTel Collector + AWS exporters + 애드온 배포임을 구조로 이해합니다
2. EKS 애드온 + IRSA로 ADOT를 배포합니다 (14 패턴의 재사용)
3. 하나의 파이프라인에서 메트릭→AMP, 트레이스→X-Ray 분배를 구성합니다
4. awsemf exporter(메트릭→CW EMF)와 Container Insights의 관계를 압니다
5. "ADOT vs 순정 OTel Collector"의 판단(지원·통합 vs 최신·중립)을 세웁니다

## 선행: 11(OTel Collector — 필수), 14(AMP·IRSA), 13(CW) · 도구: EKS, eksctl, kubectl
## 비용: ⚠️ 발생 — AMP 샘플·X-Ray 트레이스·CW. cleanup.sh 필수

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-adot-addon-pipelines.md](./lab-01-adot-addon-pipelines.md) — 애드온·IRSA·분배 파이프라인
3. [lab-02-emf-and-judgment.md](./lab-02-emf-and-judgment.md) — awsemf·수집 통합·판단
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
