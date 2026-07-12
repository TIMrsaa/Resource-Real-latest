# 학습 가이드 — 앱 밖의 구간이 보인다는 것

## X-Ray의 고유 가치 — 질문 하나로

04부터 트레이스의 목적은 "요청의 여정"이었습니다. 그런데 EKS 위 실전 여정엔 앱만 있지 않습니다:

```
사용자 → [ALB] → [인그레스] → 앱A → 앱B → [SQS] → 워커 → [DynamoDB]
          ↑ 여기서 느리면?              ↑ 큐 대기가 길면?    ↑ 스로틀이면?

Jaeger/Tempo(오픈소스): 앱 구간(계측한 곳)만 보입니다
  → ALB·SQS·DynamoDB 구간은 블랙박스 (앱 span 사이의 "공백"으로 추정만)
X-Ray: AWS 관리 서비스들이 트레이스에 직접 참여
  → ALB가 세그먼트를, DynamoDB 호출이 서브세그먼트를 남김
  → "AWS 인프라까지 이어진 여정" — 이것이 X-Ray를 고르는 이유의 핵심
```

AWS 위에서 "어디가 느린가"의 상당수가 앱 밖(관리 서비스·인프라)에서 납니다 — 그 구간이 보이는가가 X-Ray 판단의 축입니다.

## 모델 번역 — OTel 사용자를 위한 X-Ray

```
OTel(04·11)            X-Ray
trace                  trace
span                   segment(서비스 단위) / subsegment(내부 작업)
attributes             annotations(★인덱스됨 — 검색 가능) / metadata(비인덱스)
trace_id (128bit)      1-{시각}-{96bit} 형식 (awsxray exporter가 변환 — 16)
traceparent 헤더        X-Amzn-Trace-Id 헤더 (겸용 propagator — 16)

annotations vs metadata가 실무 포인트:
  검색(필터 표현식)에 쓸 키는 annotation으로 — 단 개수 제한·인덱스 비용
  나머지 상세는 metadata로 (트레이스 열면 보이지만 검색 불가)
  → 03의 "라벨 vs 본문" 구분과 같은 사상!
```

## 서비스 맵 — 공짜로 얻는 의존 그래프

```
트레이스 데이터에서 자동 생성되는 그래프:
  노드 = 서비스(+AWS 리소스), 엣지 = 호출 관계
  노드마다: 요청율·에러율·p50/p90 지연 (RED가 그래프 위에!)
→ cncf 42(Backstage)의 의존 그래프가 "선언"이라면,
  서비스 맵은 "관측된 사실"의 그래프 — 실제 트래픽이 그린 지도
→ 조사 동선: 맵에서 빨간 노드/느린 엣지 → 해당 트레이스들 → 세그먼트 상세
```

## 샘플링 규칙 — 중앙에서 관리하는 head

```
X-Ray 샘플링 규칙: 콘솔/API에서 정의, SDK/ADOT가 주기적으로 받아 적용
  기본: 초당 1개 + 초과분의 5% (reservoir + rate)
  규칙: 서비스·경로·메서드별로 다른 비율 (중앙에서 일괄 변경!)
  → "배포 없이 샘플링 조정"이 가능한 구조 (OTel 정적 설정과의 차이)

16의 접합부 정리 재확인:
  OTel 파이프라인 중심이면: OTel 샘플러가 결정, X-Ray는 받은 것 저장
  X-Ray 규칙 중심이면: ADOT에 xray 샘플러 연동 구성
  → 어느 쪽이든 "결정 지점은 한 곳" (16의 교훈)
```

## 판단 미리보기 — X-Ray vs Jaeger/Tempo

```
X-Ray: AWS 관리 서비스 참여(앱 밖 구간!), 운영 제로, 중앙 샘플링,
      CloudWatch·AMG 통합 / 대가: AWS 종속, 보존·기능의 고정
Tempo/Jaeger: 표준 생태(Grafana 상관·TraceQL), 이식성, 보존 자유
      / 대가: 운영(또는 관리형 Tempo), AWS 인프라 구간은 안 보임
→ "AWS 서비스 의존이 깊은가"가 1축, "Grafana 상관 완성도"가 2축
```
