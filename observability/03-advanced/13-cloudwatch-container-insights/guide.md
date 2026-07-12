# 학습 가이드 — 관리형의 대가는 요금표를 읽는 능력

## 트랙 전환 — 부품이 바뀌고 원리는 남습니다

```
오픈소스 스택(06~12)          AWS 관리형(13~18)
Fluent Bit → Loki             Fluent Bit → CloudWatch Logs (13)
Prometheus                    AMP (14)
Grafana                       AMG (15)
OTel Collector                ADOT (16)
Tempo/Jaeger                  X-Ray (17)
OpenSearch(자체)              OpenSearch Service (18)

바뀌는 것: 저장·운영의 주체 (서버 운영 → AWS)
남는 것: 수집기(Fluent Bit·Collector)·규약(구조화·trace_id·라벨)·
        동선(메트릭→트레이스→로그) — intermediate의 전부가 재사용됩니다
```

관리형의 판단 축(09·39·40의 "관리형 우선")이 관측에도 적용됩니다 — 단, 관리형의 대가는 운영이 아니라 **요금**이고, 요금표를 읽는 능력이 새 운영 기술이 됩니다.

## CloudWatch 요금의 물리 — 이 모듈의 중심

```
CloudWatch Logs 요금의 3요소 (대략적 구조 — 최신 요금표 확인):
  ① ingest (수집): GB당 — ★ 가장 비쌉니다 (표준 클래스 기준)
  ② 저장: GB·월당 — 상대적으로 저렴
  ③ 쿼리 (Logs Insights): 스캔한 GB당

함의 (설계를 지배):
  "일단 다 보내고 나중에 지우자" → ingest에서 이미 다 냈습니다 (지워도 소용없음!)
  → 통제는 보내기 전에: Fluent Bit 필터(06의 수문이 여기서 돈이 됩니다)
  저장이 싸다고 보존 무한? → 쿼리 스캔 비용 + 규정 고려해 보존 설정
  대량 장기 보관 → CW가 아니라 S3 (07의 copy 계층화가 여기서 실전)
  Infrequent Access 클래스: ingest 싸고 기능 제한 — 등급별 선택지
```

02(로그 폭주)·06(필터) 때 "비용"이라 부르던 것이 여기서 청구서의 숫자가 됩니다.

## Container Insights — 아는 부품의 재포장

```
Container Insights (EKS 애드온 amazon-cloudwatch-observability):
  = CloudWatch agent (메트릭: 노드·Pod 리소스 → CW 메트릭)
  + Fluent Bit (로그: /var/log/pods → CW Logs)          ← 06 그대로!
  → 애드온 하나로 "EKS 기본 관측 세트"

우리의 우위: 06을 팠으므로 이 애드온의 Fluent Bit 설정을 읽고
  커스터마이즈(필터 추가 = 비용 절감)할 수 있습니다 — 블랙박스가 아닙니다
```

## 컨트롤 플레인 로깅 — EKS에서 05의 완성

```
자체 클러스터(05): audit을 API 서버 플래그로 직접
EKS: 컨트롤 플레인이 AWS 관리 → 로그도 옵션으로 켭니다
  api / audit / authenticator / controllerManager / scheduler
  → CloudWatch Logs 그룹으로 (/aws/eks/<cluster>/cluster)
  → "누가 이 시크릿을 읽었나"(05)를 Logs Insights로 쿼리

주의: audit은 볼륨이 큽니다 — 켜는 순간 ingest 요금 (필요한 것만, 기간 한정도 전략)
```

## Logs Insights — 세 번째 쿼리 언어

02(grep)→12(LogQL)에 이어 세 번째입니다. 다행히 개념은 같습니다:

```
LogQL:        {namespace="shop"} | json | event="pg_timeout"
Logs Insights: fields @timestamp, event, user_id
              | filter event = "pg_timeout"
              | stats count() by user_id
→ 구조화 로그(02)의 보상이 여기서도 — JSON 필드가 자동 발견됩니다
→ 차이: 스캔 과금 — 시간 범위를 좁히는 습관이 곧 비용 습관
```

## 이 모듈의 비용 가드레일 (실습 수칙)

```
□ 로그 그룹마다 보존(retention) 설정 — "Never expire" 방치 금지
□ audit 로깅은 실습 후 끄기 (cleanup.sh)
□ Logs Insights는 시간 범위를 짧게 (스캔 과금)
□ 실습 후 로그 그룹 삭제 + 클러스터는 eks 파트 정책대로
```
