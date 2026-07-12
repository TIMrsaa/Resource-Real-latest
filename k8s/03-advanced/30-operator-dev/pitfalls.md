# 흔한 함정 5선

## 1. 이벤트 기반으로 짜기 ("뭐가 바뀌었지?")

oldObject/newObject diff에 의존하는 로직 — 컨트롤러 재시작/이벤트 유실/캐시 재동기화에서 영구 불일치를 만듭니다. Reconcile은 **"입력은 이름뿐, 현재 전체 상태에서 수렴"** — 프레임워크가 diff를 안 주는 것은 결핍이 아니라 강제된 미덕입니다.

## 2. 캐시 읽기 직후의 일관성 기대

`r.Create(...)` 직후 `r.Get(...)`이 NotFound — 캐시(informer)가 아직 따라오지 않아서입니다. "쓰고 바로 읽기"가 필요한 설계 자체를 피하세요 (방금 만든 객체는 손에 있는 변수로 충분). 정말 필요하면 APIReader(캐시 우회)가 있지만 비용을 압니다.

## 3. status 갱신마다 reconcile 재유발 루프

status를 Update하면 그 변경이 다시 watch 이벤트 → reconcile → status Update → ... CPU를 태우는 셀프 루프. controller-runtime은 기본적으로 status-only 변경에 대해 GenerationChangedPredicate 등으로 거를 수 있습니다 — For()에 predicate를 걸거나, status가 실제로 달라질 때만 Update하는 비교 로직을 넣어라.

## 4. 무한 RequeueAfter 폴링

외부 API 상태를 1초마다 RequeueAfter로 폴링 — CR 수천 개면 컨트롤러와 외부 API가 같이 죽습니다. 외부 변화는 가능하면 이벤트(웹훅 수신 → 큐 주입)로, 폴링이 불가피하면 간격을 길게 + 지터.

## 5. 컨트롤러 RBAC 과대 (마커 복붙)

예제에서 verbs=*를 복붙 — 컨트롤러 침해 = 그 권한 전부 탈취(모듈 11). 마커는 코드가 실제 호출하는 동사만. `make manifests` 후 생성된 Role을 리뷰 대상에 포함하세요.

## 실무 사고 사례

> 사내 Operator가 status에 "마지막 동기화 시각"을 매 reconcile마다 기록했습니다 — 함정 3의 완성형. status 변경 → watch → reconcile → status 변경의 무한 루프가 CR 800개에서 동시에 돌며 **API 서버에 초당 수천 업데이트** (모듈 21 APF가 막아준 덕에 클러스터는 살았지만 컨트롤러는 429 폭격). 수정: 시각 기록을 제거하고 의미 있는 상태 변화만 기록 + predicate 필터. 교훈: **status는 "관찰의 요약"이지 로그가 아닙니다.** 매번 달라지는 값(타임스탬프, 카운터)을 status에 넣는 순간 루프의 씨앗이 심깁니다.
