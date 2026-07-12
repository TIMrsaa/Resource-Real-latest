# 이론 — CW 구조, 컨트롤 플레인 로깅, Container Insights 해부, Logs Insights, 요금의 물리

> **🌱 17세 눈높이 비유: 유료 사물함 서비스**
> - **자체 창고(Loki 자체 운영)** = 창고를 직접 지음 — 운영은 내 몫, 공간은 내 마음
> - **CloudWatch(역 앞 유료 사물함)** = 관리 걱정 없음. 대신 **넣을 때마다 돈**(ingest) — 보관료는 싸지만 넣는 요금이 비쌈
> - **함의** = "일단 다 넣고 나중에 버리자"는 최악 — 넣는 순간 이미 냈습니다. 넣기 전에 골라내야(수문)
> - **장기 보관은 컨테이너 창고(S3)로** = 사물함(즉시 조회)엔 최근 것만, 박스째 보관은 싼 창고에
> - **Logs Insights(사물함 뒤지기 서비스)** = 뒤진 칸 수만큼 과금 — 어느 칸(시간 범위)인지 좁혀서 요청
> - **컨트롤 플레인 로깅** = 건물 관리실(AWS)이 관리하는 CCTV — 신청하면 내 사물함(로그 그룹)으로 사본이 옴 (사본 요금 발생)

---

## 1. CloudWatch 구조 (Prometheus 세계와의 대응)

```
CloudWatch Logs:
  로그 그룹(보존 정책 단위) > 로그 스트림(소스 단위) > 이벤트
  ↔ Loki의 스트림과 유사하되 관리형 (12)

CloudWatch Metrics:
  네임스페이스 > 메트릭 > 디멘션(=라벨, ★ 조합마다 커스텀 메트릭 과금!)
  해상도: 표준 1분 / 고해상도 1초 (더 비쌈)
  ↔ Prometheus 시계열 (08) — 디멘션 카디널리티 = 요금 (03의 물리가 요금으로)

CloudWatch Alarms:
  메트릭 임계·기간(evaluation periods = for와 유사) → SNS 등
  ↔ Alertmanager (10) — 단 라우팅·그룹핑·억제는 훨씬 단순
  composite alarm으로 조합 가능

메트릭 필터: 로그에서 메트릭 추출 (LogQL의 rate와 유사 발상, 12)
```

## 2. EKS 컨트롤 플레인 로깅 (05의 관리형 완성)

```
5종 (클러스터 설정에서 선택):
  api               API 서버 로그
  audit             ★ 감사 — "누가 무엇을" (05의 그것)
  authenticator     IAM 인증 (EKS 특유 — aws-auth 문제 조사!)
  controllerManager 컨트롤러
  scheduler         스케줄링 결정 (FailedScheduling 심층)

행선지: /aws/eks/<cluster>/cluster 로그 그룹
설정: eksctl utils update-cluster-logging --enable-types audit,...

판단:
  audit: 보안·규정에 필수적이나 볼륨 큼 — 보존 짧게 + 필요시만
  authenticator: EKS 접근 문제("왜 kubectl이 forbidden?") 조사의 열쇠
  나머지: 문제 조사 시 한시 활성화 전략도 유효
```

## 3. Container Insights 해부 (아는 부품의 재포장)

```
EKS 애드온 amazon-cloudwatch-observability =
  ① CloudWatch agent (DaemonSet):
     노드·Pod·컨테이너 리소스 메트릭 → CW 메트릭 (Container Insights 네임스페이스)
     → 08의 cAdvisor+node-exporter 역할의 CW판
  ② Fluent Bit (DaemonSet):                        ← ★ 06 그대로!
     /var/log/pods tail → CW Logs 그룹들로
     (application / dataplane / host 그룹 분리)

06의 지식이 주는 힘:
  애드온의 Fluent Bit 설정(ConfigMap)을 읽을 수 있습니다
  → 필터 추가(헬스체크 제외 등) = ingest 절감 = 즉시 돈
  → 커스터마이즈 가능 여부·방식은 애드온 버전 문서 확인

CW 콘솔의 Container Insights 화면:
  클러스터→노드→Pod 드릴다운 대시보드가 자동 — 09의 L1~L3를 기본 제공
  (단 RED는 앱 메트릭이 필요 — 애드온은 리소스 중심 = USE 계열)
```

## 4. Logs Insights 문법 (세 번째 쿼리 언어, 같은 개념)

```
fields @timestamp, @message, event, user_id   # 표시 필드 (JSON 자동 발견!)
| filter event = "pg_timeout"                 # 필터 (LogQL의 | 필터)
| filter @message like /timeout/              # 본문 검색 (|= 대응)
| stats count() by user_id                    # 집계 (02 lab-02의 질문!)
| sort @timestamp desc | limit 20

audit 조사 예 (05의 질문들):
  filter @logStream like /audit/
  | filter verb = "delete" and objectRef.resource = "deployments"
  | fields user.username, objectRef.name, @timestamp

비용 습관: 시간 범위 최소화 (스캔 GB 과금) — 자주 쓰는 조사는
  대시보드/메트릭 필터로 승격 (반복 스캔 방지)
```

## 5. 요금의 물리 — 설계 판단표

```
비용 구조 (표준 클래스, 개념 — 최신 요금표 필수 확인):
  ingest ≫ 저장 > 쿼리(스캔)
  메트릭: 커스텀 메트릭·디멘션 조합·고해상도·알람 개수 과금
  Infrequent Access 클래스: ingest 절반 수준, 일부 기능 제한

판단표:
  실시간 조회·알람 필요한 로그      → CW Logs (표준) + 짧은 보존
  조사용이지만 빈도 낮음            → CW IA 클래스 검토
  대량·장기(감사 아카이브)          → ★ S3 (Fluent Bit copy로 직행, 07)
  고카디널리티 앱 메트릭            → CW 커스텀 메트릭 비쌈 → AMP(14)가 유리
  이미 CW에 있는 플랫폼 메트릭      → 그대로 활용 (중복 수집 금지)

통제 수단 정리:
  보내기 전: Fluent Bit 필터·라우팅 (06·07 — 최대 레버리지)
  보존: 로그 그룹 retention (기본 Never expire 방치 금지!)
  계층: CW(최근·조회) + S3(장기·아카이브)
  감시: ingest 볼륨 자체를 메트릭·알람으로 (22의 관측의 관측)
```

## 6. 소스/도구에서 확인하기

- CloudWatch 요금: aws.amazon.com/cloudwatch/pricing (★ 항상 최신 확인)
- Container Insights 애드온 문서 (설정·커스터마이즈)
- Logs Insights 문법: CloudWatch 문서
- eks 파트(클러스터·비용 가드레일) — 이 트랙의 실습 기반

## 요약 카드

| 질문 | 답 |
|------|----|
| CW↔OSS 대응? | Logs↔Loki, Metrics(디멘션=라벨)↔Prometheus, Alarms↔Alertmanager |
| 요금의 물리? | ingest ≫ 저장 — "나중에 지우기"는 무의미, 통제는 보내기 전(수문) |
| 컨트롤 플레인 5종? | api·audit·authenticator·CM·scheduler — audit 볼륨 주의, authenticator는 접근 조사 |
| Container Insights? | CW agent(리소스 메트릭)+Fluent Bit(로그) 애드온 — 06 지식으로 해부·커스텀 가능 |
| Logs Insights? | fields/filter/stats — 스캔 과금이라 시간 좁히기가 비용 습관 |
| 장기 보관? | CW가 아니라 S3 (copy 계층화, 07) — CW는 최근·조회용 |
| 고카디널리티 메트릭? | CW 커스텀 비쌈 → AMP(14)로 |
| 필수 설정? | 로그 그룹 retention (Never expire 방치 금지) |
