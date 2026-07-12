# 학습 가이드 — 아는 도구의 AWS 옷

## ADOT의 정체 — 새 도구가 아닙니다

```
ADOT = OpenTelemetry Collector (11의 그것)
     + AWS exporter들 (awsxray, awsemf, prometheusremotewrite의 SigV4...)
     + AWS의 빌드·검증·기술지원
     + EKS 애드온 패키징 (+ Operator 포함)

→ 11을 아는 사람에게 ADOT는 "설정 파일이 낯익은 배포판"입니다
  receivers/processors/exporters 문법 동일, 배포 3패턴 동일
  새로 배울 것: AWS exporter 설정과 IRSA 배선뿐
```

cncf 27(CRI-O)의 감각과 닮았습니다 — 업스트림(OTel)과 배포판(ADOT)의 관계. 차이가 아니라 **관계**를 이해하면 혼란이 없습니다.

## 핵심 그림 — 수집 한 번, 목적지 셋

```
[앱: OTLP 한 번만]  ← 계측은 11 그대로 (Operator 주입도 그대로)
        │
        ▼
[ADOT Collector]
  pipelines:
    traces:  otlp → ... → awsxray               (17의 데이터 공급!)
    metrics: otlp/prometheus → ... → prometheusremotewrite(AMP)  (14)
    (선택)  metrics → awsemf → CloudWatch        (13과의 접점)
        │
        ▼
[AMP(메트릭)] [X-Ray(트레이스)] [CW(선택)]
        ▼
[AMG 한 화면] (15의 데이터소스들이 채워집니다)

→ 13~15에서 만든 그릇들에 ADOT가 물을 채우는 구조
→ 앱 관점: 백엔드가 무엇이든 OTLP 하나 (11의 "Collector = 완충재" 실현)
```

## awsemf — 메트릭이 로그로 가는 기묘한 길

```
EMF(Embedded Metric Format): JSON 로그에 메트릭 정의를 심으면
  CloudWatch가 로그에서 메트릭을 자동 추출
awsemf exporter: OTel 메트릭 → EMF 로그 → CW Logs → CW 메트릭
왜 이런 길이? CW의 메트릭 API보다 고처리량 주입에 유리한 경로
Container Insights(13)의 성능 메트릭도 실은 EMF 방식
→ "CW 메트릭이 필요한 소수"에 쓰는 보조 경로 (주력 메트릭은 AMP — 13의 분업)
```

## ADOT vs 순정 OTel — 미리 보는 판단

```
ADOT: AWS 검증·지원, 애드온 통합(IRSA·업그레이드), AWS exporter 안정성
  대가: 컴포넌트 스펙트럼이 업스트림보다 보수적(검증된 것 위주),
       버전이 업스트림보다 뒤따름
순정: 최신 컴포넌트·전 기능, 중립(멀티클라우드 동일 구성)
  대가: 직접 빌드·검증·지원

판단: EKS+AWS 백엔드 중심이면 ADOT (지원·통합의 값),
     특수 컴포넌트·멀티클라우드 통일이면 순정
     ★ 설정은 호환 — 갈아타기 부담이 작습니다 (표준의 가치, 또 한 번)
```

## 이 모듈이 완성하는 것

- 17(X-Ray)의 데이터 공급선 — ADOT의 awsxray exporter
- 15(AMG)의 X-Ray 데이터소스가 채워질 준비
- AWS 관측 스택의 그림 완성: 수집(ADOT·Fluent Bit) → 저장(AMP·CW·X-Ray) → 화면(AMG)
- SIGNALS-MAP의 AWS 열이 거의 채워집니다
