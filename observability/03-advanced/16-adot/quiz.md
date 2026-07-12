# 자가 점검 퀴즈

**Q1.** ADOT의 구성과 11(OTel Collector)에서 그대로인 것·새로 배우는 것은?

**Q2.** "수집 한 번, 목적지 셋"의 구조와 그것이 앱에 주는 가치는?

**Q3.** ADOT의 IRSA는 왜 3정책인가요? "한 신호만 실종"의 진단법은?

**Q4.** awsemf(EMF)의 동작 원리와 용도·주의점은?

**Q5.** ADOT의 prometheus receiver가 여는 갈래와 판단 기준은?

**Q6.** ADOT vs 순정 OTel Collector의 판단 축은? 왜 결정이 가벼운가?

**Q7.** OTel과 X-Ray 세계의 접합부에서 충돌하는 두 가지와 브리지는?

**Q8.** "반쪽 트레이스" 사고의 두 미스터리와 수습책은?

---

## 정답

**A1.** 구성: 업스트림 OTel Collector 코어 + AWS 검증 컴포넌트 셋 + AWS exporters(awsxray·awsemf·SigV4 지원 prometheusremotewrite) + AWS의 빌드·검증·기술지원 + EKS 애드온 패키징(Operator 포함). 그대로인 것: 파이프라인 문법(receiver→processor→exporter), 배포 3패턴(sidecar/agent/gateway), memory_limiter 규율, tail 샘플링의 위치. 새로 배우는 것: AWS exporter 설정(awsxray의 region, sigv4auth extension), IRSA 3정책 배선, EMF 경로 — 즉 "새 도구"가 아니라 아는 도구의 AWS 배포판입니다(업스트림과 배포판의 관계, cncf 27의 감각).

**A2.** 구조: 앱은 OTLP로 한 번만 내보내고, ADOT의 신호별 파이프라인이 traces→awsxray(X-Ray), metrics→prometheusremotewrite(AMP), 선택적으로 filter를 거쳐 awsemf(CW)로 분배합니다. 앱에 주는 가치: 백엔드가 무엇이든·몇 개든 앱과 계측은 무변경(11의 앱이 어노테이션 하나 안 바꾸고 AWS 백엔드로 전환됨) — Collector가 완충재라는 11의 설계가 보상되는 것으로, 백엔드 교체·추가가 Collector 설정 변경으로 끝납니다.

**A3.** 목적지가 셋이라 각각의 쓰기 권한이 필요합니다: AmazonPrometheusRemoteWriteAccess(AMP), AWSXrayWriteOnlyAccess(X-Ray), CloudWatchAgentServerPolicy(EMF/CW). 하나를 빠뜨리면 그 목적지의 exporter만 403으로 실패하고 나머지는 정상이라 "메트릭은 오는데 트레이스만 없다" 같은 부분 실종이 됩니다. 진단법: Collector는 exporter별로 독립 실패하므로 exporter별 자기 메트릭(otelcol_exporter_send_failed_spans/metric_points)과 Collector 로그에서 어느 exporter가 실패하는지 확인 — 목적지별 실패 알림을 걸어 두는 것이 14의 remote_write 감시 원칙의 확장입니다.

**A4.** 원리: EMF(Embedded Metric Format)는 메트릭 정의(_aws.CloudWatchMetrics)를 심은 특수 JSON을 CloudWatch Logs에 쓰면 CW가 로그에서 메트릭을 자동 추출·등록하는 방식 — awsemf exporter가 OTel 메트릭을 이 형식의 로그로 변환합니다(고처리량 주입에 유리한 경로, Container Insights 성능 데이터도 이 방식). 용도: CW 알람·AWS 통합에 꼭 필요한 소수 지표의 보조 경로(주력 메트릭은 AMP — 13의 분업). 주의: EMF도 Logs ingest 과금 + 디멘션 조합=커스텀 메트릭 과금이라 전 메트릭을 흘리면 13의 요금 함정 둘을 동시에 밟습니다 — filter로 선별하고 EMF 로그 그룹에 retention을 설정합니다.

**A5.** prometheus receiver를 추가하면 ADOT가 /metrics 스크레이프(pull)까지 수행해 OTLP(push)와 함께 한 수집기로 통합할 수 있습니다 — Prometheus 에이전트 모드(14)의 대체 갈래이자 수집기 통합 흐름(07·11)의 종착점. 판단: 이미 kube-prometheus-stack 체계(08의 ServiceMonitor 셀프서비스·relabeling)가 자리 잡았으면 그것을 유지하고 remote_write(14)만 다는 것이 단순하고, 그린필드이거나 수집기 수 최소화를 지향하면 ADOT 통합(target allocator로 SM을 읽는 구성 포함)을 검토합니다.

**A6.** ADOT: AWS의 검증·기술지원(이슈 때 물을 곳), 애드온 수명주기(설치·업그레이드 관리), AWS exporter 조합의 안정성 — EKS+AWS 백엔드 중심 조직에 적합. 순정: contrib의 넓은 컴포넌트 스펙트럼(특수 processor/exporter)·최신 기능·멀티클라우드 동일 구성 — 특수 요구·중립성 조직에 적합. 혼합(agent는 ADOT, gateway는 순정)도 가능. 결정이 가벼운 이유: 두 배포판의 설정 문법이 호환되어 갈아타기 비용이 작습니다 — 표준(OTel)의 가치가 배포판 선택의 부담을 낮추는 것으로, ADR은 가볍게 재평가 조건만 남기면 됩니다.

**A7.** 충돌 ①: 전파 헤더 — OTel은 W3C traceparent(04), X-Ray 세계(X-Ray SDK·ALB·API Gateway)는 X-Amzn-Trace-Id를 씁니다. 서로의 헤더를 못 읽으면 경계에서 trace가 끊깁니다(전파 형식 불일치의 AWS판). 충돌 ②: 샘플링 — OTel 샘플러(head parentbased)와 X-Ray SDK 샘플링 규칙(기본 1req/s+비율)이 겹치면 이중 샘플링으로 트레이스가 기대보다 훨씬 적어집니다. 브리지: propagator를 [tracecontext, xray] 겸용으로(어느 헤더든 읽고 둘 다 쓰기 — AWS 인프라와도 이어짐), 샘플링 결정은 한 곳(OTel head → Collector tail)으로 단일화하고 X-Ray SDK 규칙은 비활성.

**A8.** 미스터리 ①(볼륨 1/10): OTel head 25%에 더해 일부 레거시 서비스의 X-Ray SDK 샘플링 규칙이 따로 적용돼 이중 샘플링 — 25%×X-Ray 규칙으로 ~2.5%만 저장. 미스터리 ②(반쪽 트레이스): OTel 서비스는 traceparent, X-Ray SDK 서비스는 X-Amzn-Trace-Id로 전파해 서로 못 읽어 경계에서 끊김 + ALB의 X-Amzn-Trace-Id를 OTel 쪽이 못 읽어(xray propagator 부재) 인프라 구간도 단절. 수습: 전 서비스 propagator 겸용화([tracecontext, xray]), 샘플링 단일화(OTel head 한 곳, X-Ray 규칙 비활성, tail은 Collector), X-Ray SDK 잔존 서비스의 OTel 순차 이관+혼재 기간 규약 문서화, 대표 경로 trace 연결 검증(04)을 전환 게이트로. 교훈: 접합부의 규약 설계가 이기종 혼재의 핵심입니다.
