# Lab 02 — Logs Insights 조사와 요금 통제

> 구조화 로그를 Logs Insights로 조사하고(02·12의 보상 확인), ingest 중심 요금 구조를 수치로 체감한 뒤, 통제 수단(필터·보존·계층화)을 실제로 겁니다.

## 0. 준비 (lab-01 이어서) — 구조화 로그 앱

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: logger
  labels: { app: logger }
spec:
  replicas: 2
  selector:
    matchLabels: { app: logger }
  template:
    metadata:
      labels: { app: logger }
    spec:
      containers:
        - name: logger
          image: busybox
          command:
            - sh
            - -c
            - |
              while true; do
                if [ $((RANDOM % 4)) -eq 0 ]; then
                  echo "{\"level\":\"error\",\"event\":\"pg_timeout\",\"user_id\":$((RANDOM%50)),\"retries\":3}";
                else
                  echo "{\"level\":\"info\",\"event\":\"payment_ok\",\"user_id\":$((RANDOM%50))}";
                fi;
                echo "GET /healthz 200";
                sleep 0.5;
              done
EOF
sleep 120   # Container Insights의 Fluent Bit이 CW로 수집
```

## 1. Logs Insights 조사 — 세 번째 언어, 같은 개념

콘솔(CloudWatch → Logs Insights)에서 로그 그룹 `/aws/containerinsights/$CLUSTER/application` 선택, 시간 15분:

```
# 질문 1: 에러 이벤트 추출 (JSON 필드 자동 발견!)
fields @timestamp, log_processed.event, log_processed.user_id
| filter log_processed.event = "pg_timeout"
| sort @timestamp desc | limit 20

# 질문 2: 유저별 실패 상위 (02 lab-02의 그 질문!)
filter log_processed.event = "pg_timeout"
| stats count() as failures by log_processed.user_id
| sort failures desc | limit 10

# 질문 3: 레벨 분포 추이
filter ispresent(log_processed.level)
| stats count() by log_processed.level, bin(1m)
```

**확인** — 02에서 grep·sed로 하던 조사, 12에서 LogQL로 하던 조사가 여기선 SQL풍으로 됩니다. JSON이 `log_processed.*` 필드로 자동 파싱된 것(애드온 Fluent Bit의 설정 덕) — **구조화(02)의 보상은 저장소가 무엇이든 따라옵니다.** 문법만 셋(grep/LogQL/Insights), 개념(필드 필터·집계)은 하나입니다.

## 2. 요금 체감 — ingest 볼륨 확인

```bash
# 로그 그룹별 수집 바이트 (CW 메트릭 IncomingBytes)
aws cloudwatch get-metric-statistics --region $REGION \
  --namespace AWS/Logs --metric-name IncomingBytes \
  --dimensions Name=LogGroupName,Value=/aws/containerinsights/$CLUSTER/application \
  --start-time $(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 3600 --statistics Sum \
  --query 'Datapoints[0].Sum'
# 예: 52428800 (50MB/시간)

# 어림 계산 (요금표 확인 후):
# 50MB/h × 24h × 30일 = 36GB/월 × ingest 단가 — 이 작은 실습 앱 2개로도!
# 프로덕션 수백 Pod면? → ingest가 지배 항목이 되는 구조를 숫자로 확인
```

**핵심 체감** — healthz 소음(전체의 1/3)도 똑같이 ingest 과금됐습니다. "나중에 지우기"는 이 돈을 돌려주지 않습니다 — 통제는 보내기 전입니다.

## 3. 통제 ① — 수문 (Fluent Bit 필터로 ingest 절감)

애드온의 Fluent Bit 설정을 커스터마이즈해 healthz를 소스에서 자릅니다:

```bash
# 애드온 버전에 따라 커스터마이즈 방식이 다름 — 개념 실습으로 ConfigMap 확인 후:
kubectl -n amazon-cloudwatch get cm fluent-bit-config -o yaml > /tmp/fb-ci.yaml
# application-log.conf의 [FILTER] 섹션에 추가 (06의 grep 필터):
#   [FILTER]
#       Name    grep
#       Match   application.*
#       Exclude log /healthz
# (애드온 관리 설정이면 애드온 구성(configuration values)으로 반영하는 것이 정석 —
#  문서 확인. 개념: "어떤 방식이든 06의 수문을 여기 건다")
```

```
효과 추정: healthz가 전체의 1/3 → ingest 1/3 절감 = 청구서의 1/3
06에서 배운 필터 한 줄이 여기서 매달 돈이 됩니다 — 그리고 균형(06의
과잉 필터 경계)도 그대로: 지울 것은 "질문이 없는 로그"만
```

## 4. 통제 ② — 보존과 계층화

```bash
# 보존: 이미 1일로 설정(lab-01). 프로덕션 관례:
#   application 7~30일 / audit 90일+(규정) / dataplane 짧게
#   → "조회할 기간"만 CW에 (저장은 싸도 무한 보존은 스캔·관리 부담)

# 계층화 (개념 — 07의 copy가 실전이 되는 지점):
#   Fluent Bit OUTPUT을 둘로:
#     cloudwatch_logs (최근 조회용, 짧은 보존)
#     s3 (장기 아카이브 — ingest 요금 구조가 다르고 저장이 훨씬 쌈)
#   → 감사·규정용 장기 보관은 S3 + Athena 쿼리가 정석 코스
#   → 18(OpenSearch)까지 배우면 "조회 빈도·패턴별 3계층"이 완성됩니다
```

## 5. 통제 ③ — 관측의 관측 (ingest 감시)

```bash
# ingest 볼륨 급증 알람 — 로그 폭주(02 사고)를 청구서 전에 잡습니다
aws cloudwatch put-metric-alarm --region $REGION \
  --alarm-name "log-ingest-spike-$CLUSTER" \
  --namespace AWS/Logs --metric-name IncomingBytes \
  --dimensions Name=LogGroupName,Value=/aws/containerinsights/$CLUSTER/application \
  --statistic Sum --period 3600 --evaluation-periods 1 \
  --threshold 500000000 --comparison-operator GreaterThanThreshold \
  --alarm-description "app log ingest > 500MB/h — 로그 폭주 의심"
# (SNS 연결은 환경에 맞게) — 02의 "로그 볼륨도 관측 대상"의 CW 구현
```

## 6. SIGNALS-MAP 갱신 (과제)

```
AWS 열 추가:
  로그: Container Insights(Fluent Bit→CW Logs) — retention 설정!·수문 커스텀
  audit: EKS 컨트롤 플레인 로깅 → CW (user=IAM 매핑)
  쿼리: Logs Insights (스캔 과금 — 시간 좁히기)
  장기: (예정) S3 계층화
  비용 감시: IncomingBytes 알람
```

## 7. 정리

```bash
kubectl delete deployment logger
bash cleanup.sh   # audit 로깅 off + 로그 그룹 삭제까지
```

## 정리

- Logs Insights: 세 번째 언어, 같은 개념(필드·필터·집계) — 구조화(02)의 보상은 저장소 불문
- ingest 볼륨을 숫자로 체감 — 소음(healthz)도 똑같이 과금, "나중에 지우기" 무효
- 통제 3종: 수문(Fluent Bit 필터=매달 돈)·보존(retention)·계층화(CW 최근+S3 장기)
- ingest 급증 알람 = 로그 폭주를 청구서 전에 (관측의 관측)
- **★ 관리형의 운영 기술 = 요금표를 설계로 번역하는 능력 (ingest ≫ 저장 → 수문이 최대 레버리지)**
