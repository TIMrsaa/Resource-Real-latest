# 흔한 함정 5선

## 1. "Contour vs Emissary vs Envoy Gateway"를 데이터플레인 비교로

이 셋은 전부 Envoy를 데이터플레인으로 씁니다 — 성능·프로토콜 지원의 상당 부분이 동일합니다(theory §3). 실제 논점은 컨트롤플레인입니다: 어떤 CRD로 설정하는가(HTTPProxy vs Mapping vs Gateway API), 운영 모델이 어떤가, Gateway API 지원 성숙도는 어떤가. "어느 게 더 빠른가"로 비교하면 대부분 무의미하고, "우리 팀이 어떤 API로 라우팅을 선언하고 싶은가"가 옳은 질문입니다. 04에서 그린 계보도를 이해하면 이 함정을 피합니다 — 로고가 다르다고 프록시가 다른 게 아닙니다.

## 2. xDS를 파일 설정처럼 다루려 함

Envoy를 K8s에서 쓰면서 정적 설정(파일)을 고집하면 Pod가 뜨고 죽을 때마다 설정이 낡습니다 — EDS가 초 단위로 바뀌어야 하는데 파일은 못 따라갑니다(lab-01 Step 4에서 확인). K8s에서 Envoy는 항상 컨트롤플레인(istiod·Contour 등)과 xDS로 연결되어야 하고, 직접 파일을 만지는 것은 컨트롤플레인 없이 독립 실행할 때(엣지 프록시 등)뿐입니다. 반대로 컨트롤플레인이 있는데 사이드카의 파일을 수동으로 바꾸면 다음 xDS 푸시가 덮어씁니다 — "설정을 바꿨는데 원복된다"의 원인.

## 3. config_dump를 볼 줄 모른 채 메시를 디버깅

메시(24)에서 "트래픽이 이상하게 라우팅된다"를 만나면 대부분 istiod의 CRD(VirtualService 등)만 들여다봅니다 — 그러나 진실은 **istiod가 실제로 Envoy에 밀어넣은 설정**이고, 그것은 사이드카의 `:15000/config_dump`(Istio의 admin 포트)에 있습니다. CRD와 실제 xDS 설정이 다를 수 있습니다(번역 버그, 충돌, 적용 지연). Envoy의 admin 인터페이스(`/config_dump`, `/clusters`, `/stats`)를 읽는 능력이 메시 디버깅의 핵심이고, 이것 없이는 "왜 이렇게 라우팅되는지"를 영원히 CRD 레벨에서만 추측하게 됩니다.

## 4. 재시도를 멱등성·budget 없이 켬

`retry_on: 5xx`를 route에 걸면 일시적 실패가 투명하게 극복되어 좋아 보입니다 — 그러나 POST 같은 비멱등 요청을 재시도하면 중복 생성(중복 결제!)이 발생하고, 백엔드가 과부하일 때 재시도가 부하를 증폭해 장애를 키웁니다(18의 KEDA 재시도 교훈과 동일). 규율: retry_on을 멱등 요청·안전한 실패 유형(connect-failure, reset)에 한정하고, `retry_budget`으로 재시도가 전체 트래픽의 일정 비율을 못 넘게 하며, `per_try_timeout`을 전체 timeout보다 짧게 둡니다. 메시가 "자동 재시도"를 제공한다고 무조건 켜는 것이 이 함정의 전형입니다.

## 5. Envoy 통계의 카디널리티 폭발

Envoy는 cluster·listener마다 수십~수백 개의 통계를 내뱉습니다 — 메시에서 서비스가 수백 개면 통계가 수만 개가 되고, 그것을 전부 Prometheus로 스크레이프하면 11에서 배운 카디널리티 폭발이 재현됩니다(각 통계가 시계열 하나). 그리고 메시의 사이드카마다 이 통계 세트가 있으니 곱해집니다. `stats_matcher`로 필요한 통계만 노출하고, 불필요한 per-endpoint 통계를 억제하며, Prometheus의 metric_relabel_configs(11)로 방어선을 둬라. "관측을 켰더니 관측 시스템이 죽었다"의 메시판입니다.

## 실무 사고 사례

> 한 회사가 Istio를 도입했습니다(24). 어느 서비스로의 트래픽 일부가 간헐적으로 503을 받는 문제가 몇 주째 미해결이었습니다. 팀은 VirtualService와 DestinationRule을 수십 번 검토했지만 설정은 완벽해 보였고, 애플리케이션 로그도 정상이었습니다(요청이 아예 도달하지 않았으니까). 전환점은 한 엔지니어가 문제 사이드카의 `curl localhost:15000/config_dump`를 실행한 순간이었습니다 — istiod가 밀어넣은 실제 클러스터 설정에 `outlier_detection`이 있었고, 그 서비스의 한 엔드포인트가 반복적으로 ejection되고 있었습니다. 원인은 그 Pod의 JVM이 GC로 가끔 느려져 몇 개의 요청이 5xx를 냈고, `consecutive_5xx: 5`(Istio DestinationRule의 기본 아웃라이어 감지) 임계를 넘어 격리됐다가, base_ejection_time 후 복귀했다가, 다시 격리되는 플래핑이었습니다. VirtualService에는 아무 문제가 없었습니다 — 답은 DestinationRule의 아웃라이어 감지 설정과 그것이 번역된 Envoy 클러스터 설정에 있었고, 그것은 `config_dump`에서만 보였습니다. 개선은 세 가지: ① 아웃라이어 감지 임계를 GC 특성에 맞게 조정(consecutive_5xx 상향, base_ejection_time 조정). ② 근본적으로 JVM GC 튜닝(진짜 원인). ③ **Envoy admin 인터페이스 읽기를 메시 운영 런북에 추가** — CRD와 실제 xDS 설정을 대조하는 절차. 회고 문장이 이 모듈의 요지였습니다: "우리는 몇 주간 **설정의 의도(CRD)**를 봤지만, 문제는 **설정의 실체(config_dump)**에 있었습니다 — 메시를 운영한다는 것은 Envoy를 읽을 줄 안다는 것입니다."
