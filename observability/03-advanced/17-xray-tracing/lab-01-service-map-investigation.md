# Lab 01 — 서비스 맵과 트레이스 조사

> 16의 ADOT 파이프라인이 공급한 트레이스로 서비스 맵을 읽고, 필터 표현식·annotation으로 조사 동선을 수행합니다. 04의 간트 읽기가 X-Ray 화면에서 재현됩니다.

## ⚠️ 비용 주의 — X-Ray는 트레이스 수집·저장·스캔에 과금. 실습 후 샘플링을 낮추고 cleanup.

## 0. 준비 (16의 상태 유지 가정: ADOT + app-a/app-b + 계측)

```bash
export REGION=ap-northeast-2
# 트래픽 재생성 (일부 느린 경로 포함 — 16의 앱 구성에 따라)
kubectl -n shop run traffic --image=curlimages/curl --restart=Never -- sh -c '
  for i in $(seq 1 60); do curl -s http://app-a:8080/order >/dev/null; sleep 0.5; done'
sleep 120
```

## 1. 서비스 맵 읽기

콘솔: CloudWatch → X-Ray traces → Service map (또는 X-Ray 콘솔)

```
보이는 것:
  [Client] → [app-a] → [app-b]
  각 노드: 평균 지연·요청율·에러율(색: 초록/주황/빨강)

읽기 훈련:
  ① 노드 색 — 어디가 아픈가 (L1 개요의 역할)
  ② 엣지 지연 — 어느 호출 구간이 느린가
  ③ app-b 클릭 → Response time 분포 — 정상 분포인가 이중 봉우리인가
     (이중 봉우리 = 두 경로 혼재의 신호 — 12 캡스톤의 30% 느린 경로!)
```

**대응 확인** — 이 맵은 우리가 그린 적 없습니다: 트레이스 데이터가 자동으로 그린 "관측된 사실"의 그래프입니다. 서비스가 늘어나면 맵도 자랍니다 — cncf 42의 선언적 카탈로그와 상호 보완(선언 vs 사실).

## 2. 필터 표현식 — 트레이스 검색

콘솔의 Traces 검색창에서:

```
# 느린 트레이스만
responsetime > 1

# 에러(5xx)만
fault

# 특정 서비스 경유 + 느림
service("app-b") AND responsetime > 1

# 조합: 최근 급증한 실패의 사례 찾기
fault AND service("app-a")
```

트레이스 하나를 열어 **간트 읽기(04)**: app-a 세그먼트 안에 app-b 호출 서브세그먼트 — 04 lab-01에서 손으로 조립한 그 구조가 화면에 있습니다. Timeline에서 각 구간의 소요를 읽고 "어디가"를 좁힙니다.

## 3. annotation — 검색 가능한 조사 차원 심기

앱에 조사용 annotation을 추가합니다 (OTel attribute → X-Ray annotation 변환):

```python
# app-a에 추가 (OTel API — 11의 수동 계측 20%)
from opentelemetry import trace
span = trace.get_current_span()
span.set_attribute("order.type", order_type)      # "express" | "normal"
```

ADOT의 awsxray exporter 설정에서 인덱스할 속성 지정:

```yaml
exporters:
  awsxray:
    region: ap-northeast-2
    indexed_attributes: ["order.type"]      # ★ 이 속성만 annotation으로
```

```
재배포·트래픽 후 검색:
  annotation.order_type = "express" AND responsetime > 1
  → "express 주문만 느린가?"라는 비즈니스 차원의 질문이 검색이 됩니다

설계 감각 (theory 1절):
  indexed_attributes에 올릴 것 = 검색·비교에 쓸 소수 차원
  나머지 속성은 metadata로 (열면 보임) — 03의 라벨 규율과 같은 절제
```

## 4. Analytics — 분포 비교로 공통 요인 찾기

```
X-Ray Analytics 화면:
  응답시간 분포 히스토그램에서 느린 쪽 봉우리를 드래그 선택
  → 선택 집합의 annotation 분포가 전체와 어떻게 다른가 표시
  → "느린 트레이스의 87%가 order_type=express" 같은 발견
→ 09의 "평균의 함정"을 분포+비교로 이기는 도구 —
  가설 없이 공통 요인을 찾는 탐색적 조사
```

## 5. AWS 구간의 가시성 (개념 확인)

```
이 실습의 앱은 K8s 안 2개뿐이라 맵이 단순하지만, 실전에서:
  ALB 인그레스 도입 → 맵에 ALB 노드가 (앱 앞 구간 지연 보임)
  SQS 워커 추가 → 큐 체류가 여정에 (04의 비동기 경계를 AWS가 릴레이)
  DynamoDB 호출 → 서브세그먼트에 스로틀 여부
→ "앱 밖 공백"이 채워지는 것 — X-Ray 판단의 1축 (guide)
  Lambda 혼합 아키텍처라면 콜드스타트 구간까지 (cncf 43의 그것이 트레이스에!)
```

## 6. 정리

```bash
# 트래픽 중단. 리소스는 lab-02에서 계속
kubectl -n shop delete pod traffic --force --grace-period=0 2>/dev/null || true
```

## 정리

- 서비스 맵 = 관측된 사실의 의존 그래프 — 노드 색(어디가)·분포(이중 봉우리)로 L1 조사
- 필터 표현식(fault·responsetime·service)으로 사례 검색 → 간트 읽기(04 그대로)
- annotation은 소수 조사 차원만(indexed_attributes) — 라벨 규율(03)의 X-Ray판
- Analytics = 분포 선택→공통 요인 비교 — 탐색적 조사 도구
- **★ X-Ray의 영토는 "앱 밖 구간"(ALB·SQS·Lambda) — 이것이 판단의 1축**
