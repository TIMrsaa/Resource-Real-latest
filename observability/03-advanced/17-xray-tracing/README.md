# 17 — X-Ray: AWS 인프라까지 잇는 트레이스

> 16에서 ADOT가 트레이스를 X-Ray로 보내기 시작했습니다. 이 모듈은 그 X-Ray를 **조사 도구로 부립니다** — 세그먼트/서브세그먼트 모델(OTel span과의 대응), 서비스 맵(의존 그래프의 자동 생성), 트레이스 조사 동선, 그리고 X-Ray의 고유 가치인 **AWS 관리 서비스와의 통합**(ALB·API Gateway·Lambda·SQS가 자동으로 트레이스에 참여 — 앱 밖 구간이 보입니다). 샘플링 규칙(중앙 관리형 — 16의 접합부 이슈), X-Amzn-Trace-Id 전파, 그리고 "X-Ray vs Jaeger/Tempo"의 판단 — AWS 통합 vs 표준 생태(Grafana 상관) — 으로 마무리합니다. 12에서 오픈소스로 완성한 상관 동선의 AWS판을 AMG에서 재현합니다.

## 학습 목표

1. X-Ray의 모델(세그먼트·서브세그먼트·주석/메타데이터)과 OTel span의 대응을 압니다
2. 서비스 맵으로 의존·병목을 읽고 트레이스 조사 동선을 수행합니다
3. AWS 관리 서비스(ALB·Lambda·SQS)가 트레이스에 참여하는 구조와 가치를 압니다
4. X-Ray 샘플링 규칙(중앙 관리)과 OTel 샘플링의 관계를 정리합니다 (16의 접합부)
5. X-Ray vs Jaeger/Tempo의 판단 축을 세우고 AMG 상관 동선을 완성합니다

## 선행: 16(ADOT — 데이터 공급, 필수), 04(trace 원리), 15(AMG) · 도구: EKS+ADOT(16 유지 상태), aws cli
## 비용: ⚠️ 발생 — X-Ray 트레이스 수집·저장·스캔 과금. cleanup.sh 필수

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-service-map-investigation.md](./lab-01-service-map-investigation.md) — 서비스 맵·트레이스 조사
3. [lab-02-sampling-and-judgment.md](./lab-02-sampling-and-judgment.md) — 샘플링 규칙·AMG 동선·판단
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
