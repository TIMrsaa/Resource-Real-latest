# Lab 02 — 샘플링 규칙·AMG 상관 동선·판단

> X-Ray 샘플링 규칙으로 "배포 없는 샘플링 조정"을 체험하고, AMG에서 AWS판 상관 동선(AMP 메트릭→X-Ray 트레이스→CW 로그)을 완주하고, 트레이스 백엔드 판단을 정리합니다.

## 0. 준비 (lab-01 이어서)

## 1. 샘플링 규칙 — 중앙에서 동적으로

```bash
# 현재 기본 규칙 확인 (1req/s + 5%)
aws xray get-sampling-rules --region $REGION \
  --query 'SamplingRuleRecords[].SamplingRule.{name:RuleName,rate:FixedRate,reservoir:ReservoirSize}'

# 규칙 추가: /order 경로는 50% (조사 강화 시나리오)
aws xray create-sampling-rule --region $REGION --cli-input-json '{
  "SamplingRule": {
    "RuleName": "order-path-boost",
    "Priority": 100,
    "FixedRate": 0.5,
    "ReservoirSize": 2,
    "ServiceName": "*", "ServiceType": "*", "Host": "*",
    "HTTPMethod": "*", "URLPath": "/order",
    "ResourceARN": "*", "Version": 1
  }
}'
```

**의미** — 앱 재배포 없이 특정 경로의 샘플링을 올렸습니다(ADOT/SDK가 규칙을 폴링해 적용하는 구성일 때). 장애 조사 중 "이 경로만 자세히"가 콘솔 조작 하나 — 정적 설정(OTel 파일) 대비 X-Ray 규칙의 운영 가치입니다. 단 16의 교훈: **결정 지점은 한 곳** — OTel 샘플러 주도 구성이라면 이 규칙은 미사용으로 두고 OTel 쪽에서 조정합니다(혼용 금지).

## 2. AMG 상관 동선 — AWS판 클릭 완주 (12 캡스톤의 재현)

AMG(15)에서:

```
① [AMP 데이터소스] p99 그래프 (16이 공급한 http_server_duration)
   → 튀는 구간 확인 "무엇이 이상한가"
② [X-Ray 데이터소스] Explore → 같은 시간대 + responsetime > 1 검색
   → 트레이스 목록 → 간트: 어느 세그먼트가 "어디가"
   (X-Ray 데이터소스의 Trace to logs 설정 시)
③ [CloudWatch 데이터소스] 그 시간대·해당 서비스 로그 그룹
   → Logs Insights: filter log_processed.trace_id = "<확인한 ID>"
   → "왜"의 서술
④ 복귀: AMP 에러율로 정량화

12(오픈소스: exemplar·derived fields)와의 차이:
  배선의 자동화 수준이 다릅니다 — 오픈소스 Grafana 생태의 상관(버튼 점프)이
  더 매끈하고, AWS판은 데이터소스 간 수동 이동이 더 섞입니다
  → 이 차이가 "Grafana 상관 완성도 우선이면 Tempo"(판단 2축)의 실감
```

## 3. 비용 확인과 통제

```bash
# 트레이스 양 확인 (과금의 기초)
aws xray get-trace-summaries --region $REGION \
  --start-time $(date -d '-1 hour' +%s) --end-time $(date +%s) \
  --query 'length(TraceSummaries)'

# 통제 수단 정리:
#   샘플링 (head 규칙/OTel + Collector tail) — 수집량의 손잡이
#   annotation 절제 — 인덱스 비용
#   보존은 고정 정책 — 장기 분석 필요하면 트레이스 요약을 메트릭으로
#     (개수는 메트릭, 사례는 트레이스 — 04의 분담이 비용 전략이기도)

# 실습 후 부스트 규칙 제거 (비용 원복)
aws xray delete-sampling-rule --region $REGION --rule-name order-path-boost
```

## 4. 판단 정리 — 트레이스 백엔드 시나리오 훈련

```
A. EKS + ALB + SQS + Lambda 혼합, DynamoDB 중심 — 운영 1명
   → X-Ray. AWS 구간 가시성이 결정적 + 운영 제로.
     (Tempo면 ALB·SQS·Lambda 구간이 영원히 블랙박스)

B. EKS 순수 마이크로서비스, Grafana 중심 문화(12의 상관 완성), 멀티클라우드 계획
   → Tempo. exemplar·derived fields의 매끈한 동선 + 이식성.

C. 과도기 (X-Ray SDK 레거시 + OTel 신규 혼재)
   → 16의 접합부 규약(겸용 propagator·샘플링 단일화) + ADOT copy로
     양쪽 전송하며 비교 후 수렴 (비용 2배는 한시 허용)

공통: 계측은 OTel(11·16)로 통일 — 백엔드 판단이 exporter 설정 문제로
     가벼워집니다. ADR + 재평가 조건(cncf 48).
```

## 5. SIGNALS-MAP 갱신 (과제)

```
트레이스 줄 완성:
  백엔드: X-Ray (ADOT awsxray) — 서비스 맵·필터 표현식·Analytics
  샘플링: OTel head 주도(규칙 미사용) 또는 X-Ray 규칙 주도 — 한쪽 명시!
  상관: AMG에서 AMP↔X-Ray↔CW (수동 이동 섞임 — 오픈소스 대비 기록)
  AWS 구간: ALB·SQS·Lambda 참여 (도입 시 자동 확장)
```

## 6. 정리

```bash
bash cleanup.sh
```

## 정리

- 샘플링 규칙 = 배포 없는 중앙 조정 — 단 OTel과 이중 적용 금지(한쪽 주도 명시)
- AMG에서 AWS판 상관 완주 — 오픈소스(12) 대비 배선 자동화의 차이를 실감
- 비용 손잡이 = 샘플링·annotation 절제, "개수는 메트릭"의 분담
- 판단: AWS 구간 가시성(X-Ray) vs Grafana 상관·이식성(Tempo) — 계측 통일이 결정을 가볍게
- **★ 13~17로 AWS 관측 스택의 조사 동선까지 완성 — 남은 선택지는 로그 저장소(18)**
