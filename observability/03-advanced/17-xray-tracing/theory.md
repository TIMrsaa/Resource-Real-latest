# 이론 — X-Ray 모델, 서비스 맵, AWS 통합, 샘플링 규칙, 판단

> **🌱 17세 눈높이 비유: 택배 여정 추적의 두 서비스**
> - **오픈소스 추적(Jaeger/Tempo)** = 내가 스티커(계측)를 붙인 구간만 기록 — 집·친구 집은 보이지만 **우체국 내부·항공사 구간은 깜깜**
> - **X-Ray(자사 물류 통합 추적)** = 그 회사(AWS)의 물류 시설(ALB·SQS·Lambda·DynamoDB)이 **자동으로 스캔 기록**을 남김 — 시설 구간까지 이어진 여정
> - **세그먼트/서브세그먼트** = 구간 기록/구간 내 세부 작업 (OTel의 span과 같은 개념, 이름만 다름)
> - **annotation(검색 태그) vs metadata(메모)** = 태그는 검색되지만 개수 제한, 메모는 열어봐야 보임 — 라벨 vs 본문(03)의 재연
> - **서비스 맵** = 실제 배송 기록으로 자동 그려진 물류 지도 — 어느 허브가 밀리는지 색으로
> - **중앙 샘플링 규칙** = 본사에서 "어느 노선을 몇 % 기록할지" 일괄 조정 — 기사(앱)마다 설정 안 바꿔도 됨

---

## 1. X-Ray 모델 (OTel 번역표)

```
trace: 요청의 여정 (개념 동일)
segment: 서비스 하나가 남기는 기록 단위 (OTel의 서버 span 근사)
subsegment: 세그먼트 내부 작업 (DB 호출·외부 API — OTel 클라이언트/내부 span)
annotations: ★ 인덱스되는 키-값 — 필터 표현식으로 검색 가능
  제한 있음 → 검색할 것만 (user_tier·order_type 같은 조사 차원)
metadata: 인덱스 안 되는 상세 — 트레이스를 열면 보임
  → annotation/metadata 구분 = 라벨/본문 구분 (03)과 같은 설계 사상
error/fault/throttle 플래그: 4xx/5xx/스로틀 구분 — 맵·검색의 색

trace ID: 1-{8자리 hex 시각}-{24자리 hex} — OTel 128bit와 형식 다름
  → awsxray exporter가 변환 (16), 시각 프리픽스 덕에 ID만으로 시점 추정
전파 헤더: X-Amzn-Trace-Id (Root=...;Parent=...;Sampled=1)
  → W3C traceparent와 겸용 propagator로 공존 (16의 접합부)
```

## 2. AWS 관리 서비스의 참여 — X-Ray의 고유 영토

```
자동 참여(대표):
  ALB/API Gateway: 요청에 X-Amzn-Trace-Id 부여·전달 (여정의 시작점)
  Lambda: 자동 세그먼트 (콜드스타트·초기화 구간까지 보임!)
  SQS/SNS: 트레이스 컨텍스트를 메시지와 함께 릴레이 (04의 비동기 경계!)
  DynamoDB·S3 등: SDK 호출이 서브세그먼트로 (스로틀·지연 보임)

의미:
  "앱 span 사이의 공백"이 채워집니다 —
  ALB 대기, SQS 큐 체류, DynamoDB 스로틀이 여정 위의 구간으로
  → EKS 앱 + 서버리스 + 관리 DB가 섞인 아키텍처에서 결정적
  → 오픈소스 스택은 이 구간이 구조적으로 안 보임 (계측 불가 영역)
```

## 3. 서비스 맵 — 관측된 사실의 그래프

```
생성: 트레이스의 세그먼트 간 관계를 집계 → 노드·엣지 그래프 자동
노드: 서비스·AWS 리소스 (에러율에 따라 색)
엣지: 호출 관계 + 트래픽·지연
노드 클릭 → 해당 구간 트레이스 목록 → 상세

조사 동선 (12의 동선과 대응):
  맵(어디가 빨간가 — L1 개요의 그래프판)
  → 필터 표현식으로 트레이스 검색: service("payment") AND fault
    responsetime > 1 AND annotation.order_type = "express"
  → 트레이스 상세(간트 — 04의 읽기 그대로)
  → (AMG에서) 해당 시각 CW Logs로 점프 — AWS판 상관

Analytics: 응답시간 분포·필터 비교 (느린 그룹의 공통 annotation 찾기)
```

## 4. 샘플링 규칙 — 중앙 관리 head

```
규칙 구조:
  reservoir(초당 고정 개수) + fixed_rate(초과분의 비율)
  기본 규칙: 1req/s + 5%
  매칭: 서비스명·호스트·URL 경로·메서드별 규칙 (우선순위)

운영의 가치:
  "결제 경로만 50%로 올려" — 콘솔/API에서 즉시, 배포 없이
  reservoir 덕에 저트래픽 서비스도 최소 샘플 확보

OTel과의 정리 (16 접합부의 결론):
  A안: OTel 샘플러 주도 (parentbased ratio + Collector tail)
       — X-Ray 규칙은 사실상 미사용. OTel 표준 중심 조직
  B안: X-Ray 규칙 주도 (ADOT/SDK가 규칙 폴링)
       — 중앙 조정의 편의. AWS 중심 조직
  금지: 양쪽 동시 적용 (이중 샘플링 — 16 사고)
```

## 5. 판단 — X-Ray vs Jaeger/Tempo (트레이스 백엔드 3파전)

```
              X-Ray                    Tempo/Jaeger(12·cncf 13)
AWS 서비스 구간  ★ 보임 (ALB·SQS·Lambda)   안 보임 (계측 영역만)
운영            제로 (관리형)              자체(가벼움~중간) 또는 관리형
상관 생태        CW·AMG 통합              Grafana 생태 (exemplar·derived) ★
쿼리            필터 표현식·Analytics      TraceQL·ID 착지
샘플링          중앙 규칙 (동적)           SDK/Collector 설정
보존·비용        고정 정책·트레이스당 과금   저장소 설계 자유 (오브젝트 스토리지)
이식성          AWS 종속                  표준 중심 (OTLP·W3C)

판단 축:
  ① AWS 관리 서비스 의존이 깊습니다(서버리스·SQS·DynamoDB) → X-Ray 가치 큼
  ② Grafana 상관(12)의 완성도가 우선 → Tempo
  ③ 혼합도 가능: ADOT copy로 양쪽 전송 (비용 2배 — 과도기·비교용)
  ★ 계측은 OTel로 통일해 두면(11·16) 백엔드 판단이 가볍습니다 — exporter 문제일 뿐
```

## 6. 소스/도구에서 확인하기

- X-Ray 문서: docs.aws.amazon.com/xray — 세그먼트·샘플링·필터 표현식
- X-Ray 요금: 수집·저장·스캔 과금 구조 확인
- 16(ADOT 공급선)·04(간트 읽기)·12(상관 동선의 원형)

## 요약 카드

| 질문 | 답 |
|------|----|
| 모델 번역? | segment/subsegment↔span, annotation(인덱스)/metadata(비인덱스)↔라벨/본문 |
| 고유 가치? | AWS 관리 서비스가 트레이스에 참여 — 앱 밖 구간(ALB·SQS·Lambda)이 보임 |
| 서비스 맵? | 관측된 사실의 의존 그래프 — RED가 노드 위에, 조사의 L1 |
| 필터 표현식? | service()·fault·responsetime·annotation.X — 검색은 annotation만 |
| 샘플링 규칙? | reservoir+rate, 중앙에서 동적 조정 — OTel과 이중 적용 금지(한쪽 주도) |
| SQS 구간? | 컨텍스트가 메시지와 릴레이 — 04의 비동기 경계를 AWS가 해결 |
| vs Tempo? | AWS 구간 가시성 vs Grafana 상관 생태 — 계측을 OTel로 통일하면 결정 가벼움 |
| 비용 축? | 트레이스 수집·저장·스캔 과금 — 샘플링이 비용 손잡이 |
