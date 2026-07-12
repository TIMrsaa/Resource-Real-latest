# 이론 — ADOT 구조, 애드온·IRSA, 분배 파이프라인, EMF, 판단

> **🌱 17세 눈높이 비유: 공식 인증 택배 허브**
> - **OTel Collector(범용 물류 허브)** = 어떤 짐(신호)이든 받아 분류·배송 — 11에서 지은 그것
> - **ADOT(공식 인증 허브)** = 같은 허브 설계도에, 특정 회사(AWS) 배송지 전용 출구(awsxray·AMP용 SigV4)와 **공식 인증·AS**가 붙은 버전
> - **수집 한 번, 목적지 셋** = 보내는 사람(앱)은 허브 주소(OTLP) 하나만 알면 됨 — 등기(트레이스)는 X-Ray 창구로, 정기 화물(메트릭)은 AMP 창구로 허브가 분류
> - **EMF(화물을 편지로)** = 어떤 창구(CW)는 편지(로그)에 화물 명세를 적어 보내면 알아서 화물(메트릭)로 등록 — 특이하지만 대량 접수에 유리한 우회로
> - **판단** = 이 회사 배송지 위주면 인증 허브(AS 되는 게 값), 전 세계 배송이면 범용 허브

---

## 1. ADOT의 구성 (11과의 관계)

```
ADOT 배포판에 포함:
  OTel Collector (업스트림 코어 + AWS 검증 컴포넌트 셋)
  AWS exporters: awsxray(트레이스→X-Ray), awsemf(메트릭→CW EMF),
                prometheusremotewrite(SigV4 지원 — AMP)
  receivers: otlp, prometheus(스크레이프도 가능!), awscontainerinsight 등
  EKS 애드온: aws-otel-collector 배포 + (Operator 방식 선택 가능)

11과 동일한 것: 파이프라인 문법, 배포 3패턴(sidecar/DS/gateway),
  memory_limiter 규율, tail 샘플링의 위치(gateway)
다른 것: exporter의 인증(SigV4/IRSA), 컴포넌트 셋의 범위(보수적),
  버전 흐름(업스트림 추종)
```

## 2. 배포 — 애드온과 IRSA (14 패턴 재사용)

```
IRSA: 하나의 SA에 세 정책이 필요할 수 있습니다
  AmazonPrometheusRemoteWriteAccess  (AMP)
  AWSXrayWriteOnlyAccess             (X-Ray)
  CloudWatchAgentServerPolicy        (EMF/CW — 선택)
→ eksctl create iamserviceaccount --attach-policy-arn 3개

애드온: aws eks create-addon --addon-name adot
  (Operator 설치 — cert-manager 전제, 11과 동일)
  → OpenTelemetryCollector CRD로 Collector 정의 (11의 문법 그대로)
배포 패턴 판단도 11 그대로: agent(DS) → gateway 조합, 소규모는 단독
```

## 3. 분배 파이프라인 — 이 모듈의 본체

```yaml
receivers:
  otlp: { protocols: { grpc: {}, http: {} } }
processors:
  memory_limiter: {...}          # 11의 규율 그대로
  k8sattributes: {}
  batch: {}
exporters:
  awsxray:                       # 트레이스 → X-Ray (17)
    region: ap-northeast-2
    # ★ X-Ray는 자체 trace ID 형식 — awsxray exporter가 OTel↔X-Ray 변환
  prometheusremotewrite:         # 메트릭 → AMP (14)
    endpoint: <AMP_ENDPOINT>api/v1/remote_write
    auth: { authenticator: sigv4auth }
extensions:
  sigv4auth: { region: ap-northeast-2, service: aps }
service:
  extensions: [sigv4auth]
  pipelines:
    traces:  { receivers: [otlp], processors: [memory_limiter, k8sattributes, batch], exporters: [awsxray] }
    metrics: { receivers: [otlp], processors: [memory_limiter, batch], exporters: [prometheusremotewrite] }

★ "수집 한 번, 목적지 셋"의 실체 — 앱은 OTLP 하나,
  신호별 파이프라인이 각자의 AWS 목적지로
★ prometheus receiver를 추가하면 ADOT가 스크레이프도 대신할 수 있습니다
  (Prometheus 에이전트 모드의 대안 — 수집기 통합의 한 갈래)
```

## 4. X-Ray 형식 변환 — 17의 예고

```
OTel trace ID: 128bit 랜덤 / X-Ray trace ID: 시간 프리픽스 포함 형식
→ awsxray exporter가 변환 담당
   (SDK 단계에서 X-Ray 호환 ID 생성기를 쓰는 구성도 있음 — 17에서)
전파: W3C traceparent(04) ↔ X-Amzn-Trace-Id 헤더의 세계가 공존
→ ALB·API Gateway 등 AWS 인프라가 X-Amzn-Trace-Id를 쓰므로
  "AWS 관리 서비스까지 잇는 트레이스"가 X-Ray 선택의 이유가 됩니다 (17)
```

## 5. awsemf — 메트릭의 로그 경유로

```
EMF: CloudWatch Logs에 특수 JSON(_aws.CloudWatchMetrics 정의 포함)을 쓰면
  CW가 로그에서 메트릭을 자동 생성
awsemf exporter: OTel 메트릭 → EMF 로그 → CW
용도:
  CW 알람·대시보드에 필요한 소수 지표 (주력은 AMP — 13의 분업 유지)
  Container Insights의 성능 데이터도 이 방식 (13에서 본 것의 정체)
주의: EMF도 결국 Logs ingest 과금 + 디멘션=커스텀 메트릭 과금 (13의 물리)
  → "CW에 꼭 필요한 것만" — 분배 설계의 일부
```

## 6. 판단 — ADOT vs 순정 OTel Collector

```
ADOT: AWS 지원(이슈 때 물을 곳!)·애드온 수명주기·검증된 안정성
     AWS exporter 조합의 확실한 동작
순정: 최신 컴포넌트 전부(contrib의 넓은 스펙트럼), 멀티클라우드 동일 구성
기준:
  EKS + AWS 백엔드(AMP·X-Ray·CW) 중심 → ADOT (통합·지원의 값)
  특수 processor/exporter 필요, GCP·자체 백엔드 혼재 → 순정
  ★ 설정 문법 호환 → 갈아타기 부담 작음 (결정이 가볍습니다 — ADR 가볍게)
혼합 현실: agent는 ADOT(애드온 편의), gateway는 순정(특수 기능) 같은
  조합도 가능 — 층별 판단
```

## 7. 소스/도구에서 확인하기

- ADOT: aws-otel.github.io — collector 설정·EKS 애드온
- awsxray·awsemf exporter 문서 (컴포넌트 옵션)
- 11(Collector 원리)·14(IRSA·AMP)·17(X-Ray 소비)

## 요약 카드

| 질문 | 답 |
|------|----|
| ADOT 정체? | OTel Collector + AWS exporters + 검증·지원 + 애드온 — 새 도구 아님 |
| 11에서 그대로인 것? | 파이프라인 문법·배포 3패턴·limiter 규율·tail 위치 |
| 새로 배우는 것? | AWS exporter 설정(awsxray·sigv4auth)·IRSA 3정책·EMF |
| 핵심 그림? | 수집 한 번(OTLP) → traces→X-Ray, metrics→AMP, (선택)→CW |
| EMF? | 메트릭을 특수 JSON 로그로 → CW가 추출 — 소수 CW 지표용 (과금 주의) |
| X-Ray ID? | 형식이 다름 — awsxray exporter가 변환 (전파 헤더 공존은 17) |
| ADOT vs 순정? | AWS 중심=ADOT(지원·통합) / 특수·멀티클라우드=순정 — 설정 호환이라 결정 가벼움 |
| 스크레이프 통합? | prometheus receiver로 ADOT가 수집까지 — 수집기 통합의 갈래 |
