# 이론 — 4형, 노출 형식, rate의 감각, histogram, 두 파이프라인, 라벨 설계

> **🌱 17세 눈높이 비유: 자동차 계기판의 네 가지 숫자**
> - **counter(주행 총거리계)** = 계속 올라가기만 함. "총 12만km"보다 "요즘 하루 몇 km 뛰나"(rate)가 의미. 계기판 교체(재시작)하면 0부터
> - **gauge(속도계·연료계)** = 지금 값이 그대로 의미. 오르내림
> - **histogram(과속 단속 카메라의 구간 통계)** = "60 이하 900대, 80 이하 990대, 100 이하 1000대" — 구간 개수로 "상위 1% 속도"를 근사
> - **summary(차에 달린 자체 통계 컴퓨터)** = 차 안에서 이미 p99를 계산해 보여줌 — 정확하지만 다른 차와 합칠 수 없음
> - **두 파이프라인** = 엔진 제어용 실시간 센서(ECU가 씀 = metrics-server/HPA) vs 블랙박스 기록(사고 조사용 = Prometheus). 같은 차의 다른 목적 시스템
> - **라벨** = 장부의 분류 칸(차종·색상은 OK) — 그런데 "승객 주민번호"를 칸으로 만들면 장부가 무한히 두꺼워짐(카디널리티 폭발)

---

## 1. 메트릭 4형

```
counter (누적 카운터):
  성격: 단조 증가, 재시작 시 0 리셋
  예: http_requests_total, errors_total, bytes_sent_total
  읽기: ★ 절대값 무의미 → rate()/increase()로 (2절)
  관례: 이름 끝 _total

gauge (순간값):
  성격: 오르내림, 현재 상태
  예: memory_usage_bytes, queue_length, temperature
  읽기: 그대로 (또는 min/max/avg_over_time으로 추세)

histogram (분포 — 버킷 카운터):
  성격: 관측값을 버킷(le=경계 이하 누적)에 분류
  노출: _bucket{le="0.1"}, _bucket{le="0.5"}, ..., _sum, _count
  예: http_request_duration_seconds
  읽기: histogram_quantile(0.99, rate(..._bucket[5m])) → p99 근사
  강점: ★ 서버 간 합산 가능 (버킷끼리 더하면 전체 분포)

summary (분포 — 사전 계산 분위수):
  성격: 앱이 p50/p99를 직접 계산해 노출
  강점: 정확한 분위수 / 약점: ★ 합산 불가 (p99들의 평균은 무의미)
  → 다중 인스턴스 세계(K8s)에선 histogram이 표준, summary는 드묾
```

## 2. counter와 rate — "원본은 누적, 해석은 쿼리"

```
왜 누적으로 노출하나:
  앱이 "초당 값"을 내면 평균 창이 고정됨 (소비자가 못 바꿈)
  누적이면 소비자가 어떤 창으로도: rate(x[1m]), rate(x[1h])
  scrape 실패 한 번에도 강함 (다음 성공 때 차이로 복원)

rate(x[5m])의 의미:
  5분 창 안의 증가분 / 시간 = 초당 증가율
  counter 리셋(재시작으로 값이 내려감)을 자동 보정

increase(x[1h]): 1시간 동안의 증가량 (rate × 시간)

★ 실무 규칙: counter를 그래프에 그대로 그리지 마세요 (우상향 직선일 뿐)
  counter가 보이면 반사적으로 rate()
```

## 3. Prometheus 노출 형식 (텍스트)

```
# HELP http_requests_total Total HTTP requests.
# TYPE http_requests_total counter
http_requests_total{method="GET",path="/api",code="200"} 10234
http_requests_total{method="POST",path="/api",code="500"} 17
└──── 이름 ────┘└────────── 라벨 (k="v", 정렬) ─────────┘ └값┘

규칙:
  이름: [a-zA-Z_:][a-zA-Z0-9_:]* — 단위를 이름에 (…_seconds, …_bytes)
  라벨: 시계열의 차원 — {}의 조합이 다르면 다른 시계열
  HELP/TYPE: 사람·도구를 위한 메타데이터

histogram 노출 예:
  http_request_duration_seconds_bucket{le="0.1"} 9500
  http_request_duration_seconds_bucket{le="0.5"} 9900
  http_request_duration_seconds_bucket{le="+Inf"} 10000  ← 전체=_count
  http_request_duration_seconds_sum 812.3
  http_request_duration_seconds_count 10000
  → 평균 = _sum/_count, 분위수 = 버킷으로 근사
```

## 4. histogram으로 분위수 — 근사의 원리

```
p99 = "관측의 99%가 이 값 이하"인 지점
버킷: le=0.1 → 9500, le=0.5 → 9900, le=1.0 → 9990, le=5 → 10000
p99 지점 = 9900번째 관측 → le=0.5와 le=1.0 사이
→ histogram_quantile은 그 버킷 안을 선형 보간해 근사

함의:
  ① 정밀도는 버킷 경계에 달림 — 관심 구간(SLO 경계!)에 버킷을 (21)
  ② 버킷 밖(마지막 버킷 위)은 근사가 거칠어짐
  ③ 여러 인스턴스 합산 가능: sum by (le) → 전체 분포의 분위수
     (summary는 이게 안 됨 — K8s에서 histogram이 이기는 이유)
```

## 5. 두 메트릭 파이프라인 (혼동 종결)

```
① 리소스 메트릭 파이프라인 — 플랫폼의 반사신경
   cAdvisor(kubelet 내장) → metrics-server → Metrics API
                                              (metrics.k8s.io)
   소비자: kubectl top, HPA, VPA
   특성: 최신 스냅샷만 (이력 없음, 저장 없음), CPU·메모리만
        기본 15s 주기, 60s 창 평균
   목적: "지금" 스케일·조회 판단 — 가볍고 빠르게

② 모니터링 파이프라인 — 사람의 눈과 기억
   각종 /metrics → Prometheus scrape → TSDB 저장
   소비자: Grafana(09), Alertmanager(10), PromQL 조사
   특성: 이력 보존, 모든 타입, 라벨·쿼리, 커스텀 메트릭
   목적: 추세·알림·조사

"kubectl top ≠ Grafana 숫자"의 이유:
  다른 수집 주기·집계 창·시점 + top은 스냅샷, 그래프는 rate 창
  → 다른 게 정상. 어긋남을 버그로 오인하지 말 것

접점: HPA가 커스텀 메트릭으로 스케일하려면?
  → prometheus-adapter가 ②를 ①의 API(custom.metrics.k8s.io)로 노출
  → cncf 18(KEDA)은 아예 이벤트 소스로 우회 — 계보가 이어집니다
```

## 6. 라벨 설계 — 카디널리티의 문법 (cncf 11의 실무판)

```
좋은 라벨 (유한·낮은 카디널리티):
  method(≤10), code(≤20), path(라우트 패턴 — /api/orders/{id}로!),
  service, env, az, version

절대 금지 (unbounded):
  user_id, session_id, request_id, email, 원시 URL(쿼리스트링 포함),
  타임스탬프, 에러 메시지 전문
  → 이런 건 로그·트레이스의 몫 (신호 분담! — 01)

계산 습관:
  시계열 수 ≈ 각 라벨 값 수의 곱 × 메트릭 수 × 인스턴스 수
  새 라벨 추가 전에 이 곱을 계산해 보라 (22의 비용 통제)

path 함정:
  /api/orders/12345 를 그대로 라벨에 → 주문 수만큼 시계열!
  → 라우트 패턴(/api/orders/{id})으로 정규화 — 계측 라이브러리 설정
```

## 7. 소스/도구에서 확인하기

- 노출 형식: prometheus.io/docs/instrumenting/exposition_formats
- metrics-server: kubernetes-sigs/metrics-server (Metrics API)
- cncf 11: TSDB 내부·카디널리티의 물리 (이 모듈의 심화)
- 클라이언트 라이브러리: prometheus/client_golang 등 (4형 API)

## 요약 카드

| 질문 | 답 |
|------|----|
| 4형? | counter(누적→rate로)·gauge(순간값)·histogram(버킷 분포)·summary(사전 분위수, 합산 불가) |
| counter 읽기? | 절대값 무의미 — rate()/increase(), 리셋 자동 보정 |
| 왜 누적 노출? | 소비자가 아무 창으로나 해석 ("원본은 누적, 해석은 쿼리") |
| histogram 분위수? | 버킷 누적 카운터를 보간해 근사 — 버킷 설계=정밀도, 합산 가능 |
| K8s에서 summary는? | 다중 인스턴스 합산 불가라 histogram이 표준 |
| 두 파이프라인? | metrics-server(스냅샷, top·HPA) vs Prometheus(이력, 대시보드·알림) |
| top≠Grafana? | 다른 파이프라인·주기·창 — 다른 게 정상 |
| 라벨 금지? | unbounded(user_id·URL 원문·request_id) — 그건 로그·트레이스 몫 |
