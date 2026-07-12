# Part 5 — 옵저빌리티: 로그·메트릭·트레이스를 K8s·EKS·AWS에서 ✅ (26개 모듈 + reference 완료)

> **목표**: 관측 가능성(observability)을 **실무 파이프라인**으로 마스터합니다 — 신호(로그·메트릭·트레이스·이벤트)의 원리부터, 오픈소스 스택(Fluent Bit/Fluentd·Prometheus·Grafana·OTel·Loki/Tempo) 구축, AWS 관리형 스택(CloudWatch·Container Insights·AMP·AMG·ADOT·X-Ray·OpenSearch) 운영, SLO·비용·장애 대응까지. 최종적으로 관측 OSS(fluent-bit·fluentd·OpenTelemetry·Prometheus)에 기여합니다.
> **선행**: k8s 파트(필수), eks 파트(AWS 모듈), cncf 11~14(프로젝트 내부 — 병행 가능)
> **cncf 파트와의 관계**: cncf 11~14는 프로젝트의 **내부**(Prometheus TSDB·OTel 전파 스펙·Jaeger 백엔드·Fluentd 버퍼의 물리)를 팠습니다. Part 5는 그 위의 **실무** — 파이프라인 설계·배포 패턴·AWS 통합·비용·온콜 — 를 다룹니다. 내부가 궁금해지면 cncf로, 실전이 궁금해지면 여기로.

---

## 구성 방식

1. **신호의 원리** (`01-beginner/`) — 로그·메트릭·트레이스·이벤트가 K8s에서 어디서 어떻게 나오는지, 신호 지도
2. **오픈소스 파이프라인** (`02-intermediate/`) — Fluent Bit/Fluentd·Prometheus·Grafana·Alertmanager·OTel·Loki/Tempo로 풀 스택 구축
3. **AWS 관리형 + 심층** (`03-advanced/`) — CloudWatch·AMP·AMG·ADOT·X-Ray·OpenSearch, eBPF 관측, 프로파일링
4. **운영 실무** (`04-production/`) — SLO/에러 버짓, 관측 비용 공학, 장애 대응 동선, 대규모 관측
5. **기여 트랙** (`05-contributor/`) — 관측 OSS 생태계 구조와 실제 기여 (fluent-bit·OTel·Prometheus)

## 진도 체크리스트

### 01-beginner — 신호의 원리 ✅ (작성 완료)
- [x] **01-observability-foundations** — 모니터링(정한 질문) vs 관측(새 질문), MELT 분담(릴레이), **신호의 원산지 지도**, 관측=비용의 첫 인식
- [x] **02-logging-basics** — stdout 표준(12-factor), **CRI 포맷(P/F 조각)**, 로테이션=유실의 물리, --previous(유언), 구조화=계약(trace_id 규약)
- [x] **03-metrics-basics** — 4형(counter는 rate로!), histogram 분위수 근사, **두 파이프라인**(metrics-server vs Prometheus), 라벨=곱셈(unbounded 금지)
- [x] **04-traces-basics** — trace/span 트리, **traceparent 손 릴레이**, 전파 끊김 5지점(고아 trace), head/tail 샘플링, 가장 약한 고리
- [x] **05-events-and-signals-map** — Events reason 사전·로그화(휘발 극복), audit(누가?), **신호 지도 종합 + 15문항 반사 훈련**(졸업: SIGNALS-MAP.md)

### 02-intermediate — 오픈소스 파이프라인 ✅ (작성 완료)
- [x] **06-fluent-bit-pipeline** — tag/match 라우팅, CRI 파싱(P/F), kubernetes 필터, **버퍼·백프레셔**(fs 버퍼·조용한 유실), 자기 관측(dropped 알림)
- [x] **07-fluentd-aggregator** — 2층 구조(곱→합), match 순차 소비!, forward ack, **마스킹·copy 다중 배달**, 역류 사고(버퍼 격리·계단 알림)
- [x] **08-prometheus-on-k8s** — Operator·**ServiceMonitor 매칭 3연쇄**(조용한 미수집), 3대장 구분, relabeling 수문·sampleLimit, **recording rule=정의의 단일화**
- [x] **09-grafana-dashboards** — RED/USE, 변수·**드릴다운(L1→L2→L3)**·배포 마커, as code(CM 프로비저닝), 안티패턴(그래프 벽·평균)
- [x] **10-alerting-alertmanager** — **울릴 자격 3심사**(증상·행동·긴급), for/keep_firing, 라우팅·그룹핑·억제·사일런스, 알림 피로("소음이 진짜를 가린다")
- [x] **11-otel-instrumentation** — Operator 자동 주입(웹훅의 실체), **Collector 3패턴**(agent→gateway=로그 2층과 동형), tail 샘플링 배치, 오버헤드 예산
- [x] **12-loki-tempo-stack** — Loki(라벨만 인덱스)·Tempo(ID 착지), **상관 배선 3종**(derived fields·trace to logs·exemplar), 클릭 완주 캡스톤

### 03-advanced — AWS 관리형 + 심층 ✅ (작성 완료)
- [x] **13-cloudwatch-container-insights** — **요금의 물리(ingest≫저장)**, 컨트롤 플레인 로깅(audit=IAM 매핑), Container Insights 해부(=Fluent Bit), Logs Insights, retention!
- [x] **14-amp-managed-prometheus** — **절단선(수집은 우리, 저장은 AWS)**, remote_write·에이전트 모드·IRSA, 요금=시계열×빈도, dead man's switch
- [x] **15-amg-managed-grafana** — Identity Center SSO·IAM 데이터소스(키 없음), **as code는 API push로 유지**, 사용자당 과금 축, "AWS는 물리, 규약은 우리"
- [x] **16-adot** — OTel Collector의 AWS 배포판(문법 동일), **수집 한 번 목적지 셋**(AMP+X-Ray+EMF), 접합부 규약(전파 겸용·샘플링 단일화)
- [x] **17-xray-tracing** — segment/annotation(=라벨 규율), 서비스 맵(관측된 사실의 그래프), **AWS 구간 가시성**(ALB·SQS·Lambda)이 판단 1축, 공백의 목록화
- [x] **18-opensearch-logs** — 역색인(쓰기 비쌈·읽기 최강), 샤드·매핑·**ISM 노화**, 워터마크 역류 사고, **로그 3파전 결론(패턴이 정합니다)**
- [x] **19-ebpf-observability** — Hubble(verdict=즉답!)·L7 파싱, **한계 3종(내부·여정·TLS) 실증**, 영토 지도(대체 아닌 보완), eBPF 먼저→OTel 깊이
- [x] **20-continuous-profiling** — 플레임그래프·**diff(지속의 보상)**, 누수는 inuse로(의심→지목→수정→검증), 조사의 마지막 1미터(함수명), 다섯 신호 지도 완성

### 04-production — 운영 실무 ✅ (작성 완료)
- [x] **21-slo-sli-error-budget** — SLI(사용자 관점·le버킷=SLO경계), 버짓=혁신의 예산, **멀티윈도우 번레이트**(3시나리오 검증), 조직 계약(예외 절차까지)
- [x] **22-observability-cost** — 비용 방정식·**관측의 관측 3층**(볼륨·건강·비용추정+워치독), 레버리지 순서(수문>계층>보존), **정렬(삭감 아닌 재투자)**
- [x] **23-incident-response** — 완화 우선·IC 체계(조사하지 않습니다), **runbook 5요소**, 비난 없는 포스트모템, **게임데이(파트의 실기 시험)** — MTTR=기술×절차
- [x] **24-scaling-observability** — Thanos 구조(sidecar 무침습·오브젝트 스토리지)·HA dedup·**테넌시(격리·쿼터·귀속)**, 규모별 판단 지도 — **기본기가 이식성**

### 05-contributor — 기여 트랙 ✅ (작성 완료)
- [x] **25-observability-oss-landscape** — 4대 생태계 거버넌스(fluent·prometheus·**OTel SIG 체계**·grafana 기업주도), 기여 유형 지도(**자기 영토**=exporter·플러그인), 3축 선정(관심×역량×건강)
- [x] **26-contributing-observability** — **세 갈래 빌드**(C·Go·ocb 조립형), 개발 루프(내 빌드→kind→08 체계로 검증), **측정이 붙은 기여**, 첫 기여 제출(파트의 졸업 과제)

### reference ✅ (작성 완료)
- [x] cheatsheet-promql.md (실전 쿼리·함정 리마인더) / cheatsheet-pipelines.md (FB·LogQL·Insights·Collector) / glossary.md (용어+**관통 원리 10**) / links.md

---

## 실습 환경

- **로컬**: kind (오픈소스 스택 전부 — 01~12·19·20·24 대부분)
- **AWS**: EKS + 관리형 서비스 (13~18) — **비용 발생 모듈은 README에 명시 + cleanup.sh 필수 실행**
- 버전 기준: 루트 README의 버전 기준표를 따릅니다 (K8s v1.36, Helm v4)

## 관통 질문 (이 파트의 뼈대)

1. **이 신호는 어디서 태어나 어디로 흐르는가** — 모든 모듈에서 파이프라인의 경로를 그립니다
2. **무엇을 볼 수 있고 무엇이 비용인가** — 관측은 공짜가 아닙니다 (카디널리티·볼륨·보존 = 돈)
3. **장애의 순간에 쓸 수 있는가** — 대시보드가 아니라 조사 동선이 목적 (cncf 13의 확장)
4. **자체 운영 vs 관리형** — 09·39·40의 판단이 관측 스택에도 (AMP vs Prometheus, AMG vs Grafana...)

> **이 파트를 시작하려면**: 01부터 순서대로. AWS 모듈(13~18)은 eks 파트의 클러스터·비용 가드레일을 재사용합니다.

## 학습 순서 요약

1. **01~05 (신호의 원리)**: 원산지 지도·로그의 물리·메트릭 4형·전파·Events — 졸업 과제 SIGNALS-MAP.md
2. **06~12 (오픈소스 파이프라인)**: Fluent Bit→Fluentd 2층, Prometheus 체계, 대시보드·알림 규율, OTel Collector, **상관 배선(클릭 완주 캡스톤)**
3. **13~18 (AWS 관리형)**: CW(요금의 물리)→AMP(절단선)→AMG→ADOT(수집 한 번 목적지 셋)→X-Ray(AWS 구간)→OpenSearch(로그 3파전) — "AWS는 물리, 규약은 우리"
4. **19~20 (심층)**: eBPF(계측 없는 지도·한계)·프로파일링(마지막 1미터) — 다섯 신호의 영토 지도 완성
5. **21~24 (운영)**: SLO 번레이트→비용 정렬→장애 대응(**게임데이=실기 시험**)→규모(기본기가 이식성)
6. **25~26 (기여)**: 4대 생태계 정찰→세 갈래 빌드→**첫 기여 제출(졸업 과제)**

> 이 파트의 졸업장도 자격증이 아니라 **기여 이력**입니다 — 26 lab-02의 완료 조건은 문서가 아니라 제출된 기여입니다.
