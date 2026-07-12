# 자가 점검 퀴즈

**Q1.** 오픈소스 스택(06~12)과 AWS 관리형(13~18)의 대응 관계에서 "바뀌는 것"과 "남는 것"은?

**Q2.** CloudWatch Logs 요금의 3요소와 "ingest ≫ 저장"이 설계에 주는 함의는?

**Q3.** EKS 컨트롤 플레인 로깅 5종과 각각의 용도는? audit·authenticator의 EKS 특유 가치는?

**Q4.** Container Insights 애드온의 구성을 해부하세요. 06의 지식이 주는 실질적 힘은?

**Q5.** Logs Insights의 문법 요소와 비용 습관은? grep/LogQL과의 관계는?

**Q6.** CW 커스텀 메트릭의 과금 구조와 AMP와의 분업 기준은?

**Q7.** 로그 비용 통제 3종의 레버리지 순서와 이유는?

**Q8.** "관측 비용이 워크로드를 넘은" 사고의 다섯 원인과 수습책은?

---

## 정답

**A1.** 대응: Fluent Bit→Loki ↔ Fluent Bit→CloudWatch Logs, Prometheus ↔ AMP, Grafana ↔ AMG, OTel Collector ↔ ADOT, Tempo/Jaeger ↔ X-Ray, 자체 OpenSearch ↔ OpenSearch Service. 바뀌는 것: 저장·서버 운영의 주체(내가 운영 → AWS 관리형)와 비용 모델(운영 인력 → 요금). 남는 것: 수집기(Fluent Bit·Collector)와 규약(구조화 로그·trace_id·라벨 일관성)·조사 동선(메트릭→트레이스→로그) — intermediate에서 배운 원리와 부품 지식이 그대로 재사용되며, 관리형의 새 운영 기술은 "요금표를 설계로 번역하는 능력"입니다.

**A2.** 3요소: ① ingest(수집, GB당 — 가장 비쌈), ② 저장(GB·월 — 상대적으로 저렴), ③ 쿼리(Logs Insights 스캔 GB당). 함의: 비용은 로그가 CW에 **들어오는 순간** 대부분 발생하므로 "일단 다 보내고 나중에 지우자"는 무의미합니다(지워도 ingest 요금은 이미 냄). 따라서 통제의 레버리지는 보내기 전 — Fluent Bit 필터(06의 수문)가 최대이고, 대량 장기 보관은 CW가 아니라 S3로 계층화(07의 copy)하며, 보존(retention)은 조회 필요 기간만. Infrequent Access 클래스(ingest 저렴·기능 제한)도 등급별 선택지입니다.

**A3.** api(API 서버 로그), audit(감사 — 누가 무엇을, 05의 그것), authenticator(IAM 인증 로그), controllerManager, scheduler(스케줄링 결정 — FailedScheduling 심층). EKS 특유 가치: audit의 user.username에 IAM 매핑 결과가 나와 "어느 IAM 주체가 클러스터에서 무엇을 했나"가 이어집니다(IAM과 K8s RBAC의 연결). authenticator는 "왜 kubectl이 forbidden인가" 같은 접근 문제(aws-auth·access entries 매핑 실패) 조사의 열쇠입니다. 주의: audit은 볼륨이 커 보존·계층화 설계 또는 기간 한정 활성화 전략이 필요합니다.

**A4.** 구성: ① CloudWatch agent(DaemonSet) — 노드·Pod·컨테이너 리소스 메트릭을 ContainerInsights 네임스페이스의 CW 메트릭으로(08의 cAdvisor+node-exporter 역할), ② Fluent Bit(DaemonSet) — /var/log/pods를 tail해 CW Logs의 application/dataplane/host 그룹으로(06 그대로: tail·CRI 파서·kubernetes 필터, OUTPUT만 cloudwatch_logs). 06 지식의 힘: 애드온의 Fluent Bit ConfigMap을 읽고 이해할 수 있으므로 블랙박스가 아닙니다 — 필터 추가(헬스체크 제외 등)로 ingest를 직접 절감하고, 문제(수집 누락·버퍼) 발생 시 06의 진단(메트릭·버퍼 설정)을 그대로 적용할 수 있습니다.

**A5.** 문법: fields(표시 필드 — JSON이 자동 발견됨), filter(필드·본문 조건), stats ... by(집계), sort/limit, bin(시간 버킷). 비용 습관: 스캔한 GB만큼 과금되므로 시간 범위를 최소로 좁히고, 반복되는 질문은 메트릭 필터로 승격해 재스캔을 방지합니다. 관계: grep(02)→LogQL(12)→Logs Insights로 문법은 셋째지만 개념(구조화 필드의 필터·집계)은 하나입니다 — 구조화 로깅(02)의 보상은 저장소가 무엇이든 따라오며, "유저별 실패 상위" 같은 질문이 어디서나 쿼리 한 줄이 됩니다.

**A6.** CW 메트릭은 디멘션(라벨) 조합마다 별도 커스텀 메트릭으로 과금됩니다 — 03의 카디널리티 물리가 메모리가 아니라 요금으로 직격하는 구조라, Pod명·경로·고객 ID 같은 조합을 디멘션으로 넣으면 청구서가 폭발합니다. 분업 기준: 플랫폼·AWS 서비스 지표와 소수의 핵심 비즈니스 지표는 CW로(알람·AWS 통합의 이점), 고카디널리티 앱 메트릭(라벨 분해가 필요한 RED 등)은 AMP(14 — Prometheus 요금 모델이 카디널리티에 상대적으로 유리)로.

**A7.** 레버리지 순서: ① 보내기 전 필터(수문 — Fluent Bit grep 등): ingest 자체를 줄여 3요소 전부(수집·저장·스캔)를 절감하는 최대 레버리지, ② 보내는 곳 분리(계층화): 장기·대량은 S3로 라우팅해 ingest 요금 구조 자체를 바꿈, ③ 보존 단축(retention): 저장 요금만 줄이는 최소 레버리지(이미 낸 ingest는 불변). 이유: 요금이 ingest 중심이므로 시간 역순(오래된 것 정리)이 아니라 파이프라인 역순(소스에서 차단)이 효과 순서입니다. 단 과잉 필터는 조사 불능이 더 비쌉니다(06의 균형).

**A8.** 원인: ① debug 레벨 전면 활성 후 미원복(볼륨 8배, ingest 알람 부재로 무인지), ② retention 전무(200개 그룹 Never expire — 수년치 저장), ③ 고카디널리티 커스텀 메트릭 증식(디멘션 조합 과금), ④ audit 3클러스터 상시 on(목적 종료 후 방치), ⑤ 5분마다 30일 범위 Insights를 도는 스크립트(스캔 과금 자동화). 수습: 수문 재정비(debug·헬스체크 차단, 기간 한정+자동 원복), retention IaC 필수화+기존 일괄 설정+S3 계층화, 메트릭 분업(고카디널리티→AMP, CW는 승인제), 비용 관측 상설화(IncomingBytes 대시보드·급증 알람·월간 리뷰), 반복 쿼리의 메트릭 필터 승격. 결과 1/5 절감·조사력 무손실. 교훈: 관리형의 장애 모드는 다운이 아니라 청구서이고, 임시 조치는 자동 원복과 짝지어야 합니다.
