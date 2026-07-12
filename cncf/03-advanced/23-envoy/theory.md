# 이론 — Envoy 구성, 요청의 여정, xDS, 컨트롤플레인 분리, 복원력, 관측

> **🌱 17세 눈높이 비유: 대형 호텔의 프런트 시스템**
> - **listener** = 호텔 정문 — 특정 포트(문)에서 손님을 받습니다
> - **filter chain** = 정문에서 객실까지의 검문 절차 — 신분 확인, 짐 검사, 안내 (인증·rate limit·헤더 조작)
> - **route** = 안내 데스크의 규칙 — "VIP는 3층, 일반은 5층" (경로·헤더로 목적지 결정)
> - **cluster** = 목적지 그룹 — "5층 객실들"
> - **endpoint** = 실제 객실 (백엔드 Pod)
> - **xDS** = 본사에서 프런트로 오는 **실시간 무전** — "지금 302호 공사 중이니 손님 보내지 마" (설정을 파일이 아니라 방송으로)
> - **컨트롤플레인** = 본사 관제실 (istiod 등) — 호텔 상황(K8s)을 보고 무전(xDS)으로 지시. 프런트(Envoy)는 무전대로 움직일 뿐
> - **서킷 브레이커** = "5층에 불나면 그 층으로 손님 안 보내기" (장애 확산 차단)

---

## 1. Envoy의 구성 — 요청의 여정

```
요청 도착
   │
   ▼ listener (0.0.0.0:8080 — 리스닝 소켓)
   │   listener filters (TLS inspector 등)
   ▼ filter chain
   │   network filters: http_connection_manager(HCM)가 핵심
   │     └ http filters: cors → jwt_authn → rate_limit → router (마지막)
   ▼ route configuration
   │   virtual_host 매칭(도메인) → route 매칭(path/header) → cluster 선택
   ▼ cluster
   │   load balancing(round_robin/least_request/ring_hash...) → endpoint 선택
   │   circuit breaker / outlier detection / health check
   ▼ upstream (백엔드로 전송)
```

핵심 개념 분리:

```
listener   = "어디서 받는가" (포트, TLS)
route      = "어디로 보내는가" (도메인·경로 → cluster)
cluster    = "무엇의 그룹인가" (백엔드 집합 + LB·복원력 정책)
endpoint   = "실제 인스턴스" (IP:port)
★ 이 4계층이 xDS의 네 종류(LDS/RDS/CDS/EDS)와 정확히 대응합니다
```

## 2. xDS — 동적 설정의 프로토콜

| xDS | 이름 | 전달하는 것 | 변화 빈도 |
|---|---|---|---|
| **LDS** | Listener Discovery | 리스너(포트·필터체인) | 낮음 |
| **RDS** | Route Discovery | 라우트 규칙 | 중간 |
| **CDS** | Cluster Discovery | 클러스터(백엔드 그룹) 정의 | 중간 |
| **EDS** | Endpoint Discovery | 엔드포인트(실제 IP들) | **높음** (Pod 뜨고 죽음) |
| SDS | Secret Discovery | TLS 인증서 (cert-manager·19와 연결) | 갱신 시 |
| ADS | Aggregated | 위 전부를 한 스트림으로 (순서 보장) | — |

```
동작:
  Envoy ──gRPC 스트림──▶ 컨트롤플레인 (xDS 서버)
        ◀── "여기 최신 클러스터 목록" (CDS 응답)
        ◀── "여기 최신 엔드포인트" (EDS 응답)
  → Envoy가 무중단으로 내부 설정 갱신 (리로드·재시작 없음!)

핵심: EDS가 높은 빈도로 바뀝니다 (Pod 스케일·재배포)
  → 파일 기반이면 못 따라갑니다. 스트림이라 가능합니다
  → 이것이 K8s 시대에 Envoy가 표준이 된 이유
```

## 3. 컨트롤플레인 분리 — 계보의 정체

```
데이터플레인(Envoy): 트래픽을 실제로 처리. 어디로 보낼지는 xDS로 받습니다
컨트롤플레인:        K8s를 watch → xDS로 번역 → Envoy에 밀어넣습니다

이것이 04의 계보도:
  istiod(Istio):     ServiceEntry·VirtualService·DestinationRule → xDS
  Contour:           Ingress·HTTPProxy CRD → xDS
  Emissary:          Mapping CRD → xDS
  Envoy Gateway:     Gateway API → xDS
  → 전부 "K8s 리소스를 Envoy 설정으로 번역하는 생성기"
  → 데이터플레인은 동일(Envoy), 컨트롤플레인의 API·모델만 다릅니다
```

**그래서 "Contour vs Emissary"는 데이터플레인 논쟁이 아니라 컨트롤플레인(어떤 CRD·운영 모델) 논쟁입니다.** 04에서 예고한 것의 결론.

## 4. 필터 체인 — 프록시가 프록시 이상인 이유

```
HTTP 필터 (HCM 안, 순서대로):
  cors              CORS 처리
  jwt_authn         JWT 검증 (인증)
  ext_authz         외부 인가 서비스 호출 (OPA 등 — 07)
  ratelimit         전역 rate limit
  lua / wasm        커스텀 로직 (WASM 확장 — 03의 Wasm이 여기서도)
  router            ★ 마지막: 실제 라우팅·업스트림 전송

★ 필터는 순서가 의미 (12의 Collector processors, 20의 CoreDNS 체인과 같은 계열)
★ router 필터는 항상 마지막 (그 앞의 필터들이 요청을 가공·검증)
```

## 5. 복원력 — cluster 수준의 방어

```
서킷 브레이커(circuit breaker):
  max_connections / max_requests / max_pending_requests / max_retries
  → 한도 초과 시 즉시 실패(빠른 실패) — 느린 백엔드가 전체를 마비시키는 것 차단

아웃라이어 감지(outlier detection):
  연속 5xx·게이트웨이 오류가 임계 초과한 엔드포인트를 일시 격리(ejection)
  → 죽어가는 인스턴스를 로드밸런싱 풀에서 자동 제외 (수동적 헬스체크)

재시도(retry):
  retry_on(5xx·reset·connect-failure), num_retries, per_try_timeout, retry_budget
  ★ 재시도는 멱등 요청에만 + budget으로 재시도 폭풍 방지 (18의 교훈과 같은 계열)

타임아웃:
  route timeout, per_try_timeout, idle_timeout (eks 14의 그 idle_timeout!)
```

이것들이 eks 14에서 ALB로 배운 L7 기능의 정체이자, 서비스 메시(24·25)가 "코드 수정 없이 복원력을 준다"고 할 때 그 복원력의 실체입니다.

## 6. 관측 — Envoy가 내뱉는 것

```
통계(stats): 수천 개의 카운터·게이지·히스토그램
  cluster.<name>.upstream_rq_2xx / _5xx / _pending_overflow (서킷 브레이커 발동!)
  cluster.<name>.upstream_rq_time (지연 히스토그램)
  cluster.<name>.outlier_detection.ejections_active (격리된 엔드포인트)
  → Prometheus로 스크레이프(11), 카디널리티 주의(cluster 수 × stat 수)

액세스 로그: 요청별 상세 (%RESPONSE_CODE% %DURATION% %UPSTREAM_HOST% ...)
분산 트레이싱: x-request-id 전파, span 생성 (12의 컨텍스트 전파와 연결)
admin 인터페이스: :9901 — /stats, /clusters, /config_dump (실시간 설정 확인!)
```

**`/config_dump`이 디버깅의 핵심**: xDS로 받은 현재 설정 전체를 JSON으로 — "istiod가 무엇을 밀어넣었나"를 여기서 봅니다.

## 7. 소스/도구에서 확인하기

- Envoy: https://www.envoyproxy.io/docs — architecture, listeners, xDS protocol
- xDS 프로토콜: https://www.envoyproxy.io/docs/envoy/latest/api-docs/xds_protocol
- config_dump: `curl localhost:9901/config_dump`
- 04 계보도 복습, 24·25(Istio·Linkerd)의 전제

## 요약 카드

| 질문 | 답 |
|------|----|
| 4계층? | listener(어디서) / route(어디로) / cluster(무엇의 그룹) / endpoint(실제 IP) |
| xDS 네 종류? | LDS/RDS/CDS/EDS — 4계층에 대응, EDS가 가장 자주 바뀜 |
| xDS가 혁명인 이유? | 설정을 파일이 아니라 gRPC 스트림으로 → Pod 변화를 무중단 반영 |
| 계보의 정체? | 데이터플레인은 다 Envoy, 컨트롤플레인(설정 생성기)만 다릅니다 |
| Contour vs Emissary? | 데이터플레인 아닌 컨트롤플레인(CRD·모델) 논쟁 |
| 필터 체인? | HTTP 필터 순서대로, router가 마지막 (인증·rate limit·WASM) |
| 복원력? | 서킷 브레이커·아웃라이어 감지·재시도(budget)·타임아웃 (메시 복원력의 실체) |
| 디버깅 급소? | admin :9901의 /config_dump (xDS가 밀어넣은 실제 설정) |
