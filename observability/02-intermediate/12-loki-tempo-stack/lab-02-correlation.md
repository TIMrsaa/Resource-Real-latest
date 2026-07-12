# Lab 02 — 상관 배선과 동선 완주 (트랙 캡스톤)

> Grafana에 세 데이터소스를 잇는 배선(derived fields·trace to logs·exemplar)을 깔고, 장애 시나리오를 "메트릭→트레이스→로그→원인"으로 **클릭 완주**합니다. intermediate 트랙의 캡스톤입니다.

## 0. 준비 (lab-01 이어서 — payment가 30% 확률로 느린 에러 중)

```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80 &
# http://localhost:3000 (admin / prom-operator)
```

## 1. 배선 ① — Loki 데이터소스 + derived fields (로그→트레이스)

Grafana UI: Connections → Data sources → Add → Loki

```
URL: http://loki.monitoring.svc.cluster.local:3100

Derived fields (핵심 설정):
  Name: TraceID
  Type: Regex in log line   (또는 JSON 필드)
  Regex: "trace_id":"(\w+)"
  Query: ${__value.raw}
  URL Label: View Trace
  Internal link: Tempo (데이터소스 선택)
```

**의미** — Loki가 로그 본문에서 trace_id를 발견하면 자동으로 "View Trace" 버튼을 답니다. 02의 규약(trace_id 필드)이 여기서 버튼이 됩니다.

## 2. 배선 ② — Tempo 데이터소스 + trace to logs (트레이스→로그)

Add → Tempo:

```
URL: http://tempo.monitoring.svc.cluster.local:3100

Trace to logs:
  Data source: Loki
  Tags: k8s.namespace.name → namespace, k8s.deployment.name → app
        (★ 트레이스 속성명 ↔ Loki 라벨명 매핑 — 06↔11의 라벨 일관성을
         이름 매핑으로 흡수하는 지점)
  Span start/end time shift: -5m / +5m
```

**의미** — 어느 span을 보다가 "Logs for this span"을 누르면, 그 시간대·그 앱의 Loki 쿼리가 자동 생성됩니다. 라벨 매핑이 어긋나면 빈 결과 — 배선 검증이 필수인 이유.

## 3. 배선 ③ — exemplar (메트릭→트레이스)

Prometheus 데이터소스(기본 존재) 설정에서:

```
Exemplars:
  Internal link: Tempo
  Label name: trace_id
```

계측 앱의 histogram에 exemplar가 실려 오면(자동 계측이 지원), Prometheus가 저장(기능 플래그는 0단계에서 켜 둠)하고 Grafana 그래프에 ◆점으로 표시됩니다.

## 4. 캡스톤 — 장애 조사 클릭 완주

시나리오: "결제가 가끔 느리고 실패한대요" (payment의 30% 에러가 그것)

```
① [메트릭] Explore → Prometheus:
   histogram_quantile(0.99, sum by (le) (rate(http_server_duration_milliseconds_bucket{k8s_namespace_name="shop"}[5m])))
   (자동 계측의 메트릭 — 이름은 환경에 따라 확인)
   → p99가 1.2s 근처로 튑니다. "무엇이 이상한가" 확인
   → 그래프의 ◆(exemplar) 클릭 → "View Trace"

② [트레이스] Tempo가 열림:
   trace 간트: GET /pay 서버 span이 1.2s — 내부에 다른 span 없음
   → "앱 내부에서 1.2s를 통째로 씀" (외부 호출 아님 — 04의 간트 읽기:
      자식 없는 긴 부모 = 자기 자신의 시간)
   → span의 "Logs for this span" 클릭

③ [로그] Loki가 열림 (시간대·앱 자동 필터):
   {namespace="shop", app="payment"} | json
   → {"level":"error","event":"pg_timeout","retries":3,"trace_id":"..."}
   → ★ 원인 도달: PG 타임아웃 + 재시도 3회가 1.2s의 정체

④ [복귀·정량화] 로그의 event로 규모 확인:
   Loki 메트릭 쿼리: sum(rate({namespace="shop"} | json | event="pg_timeout" [5m]))
   또는 Prometheus 에러율로 — "전체의 30%" 정량화 → 보고
```

**완주 확인** — 클릭 네 번으로 "무엇이(p99 급등) → 어디가(앱 내부 1.2s) → 왜(pg_timeout·재시도) → 얼마나(30%)"가 끝났습니다. 01 lab-02에서 kubectl 수작업으로 5단계 걸렸던 조사가, 배선된 스택 위에서는 분 단위입니다. **이것이 intermediate 트랙 전체가 지은 것입니다.**

## 5. 배선 검증 체크리스트 (운영 절차화)

```
□ 로그에서 View Trace 버튼이 뜨고 실제 trace가 열리나 (regex·필드명)
□ trace에서 Logs for this span이 비어 있지 않나 (라벨 매핑!)
□ 그래프에 ◆가 보이고 클릭이 trace로 가나 (exemplar 플래그·계측)
□ 신규 서비스 온보딩 시 위 셋을 확인 항목에 (배선은 조용히 끊깁니다 —
  라벨 개편·필드명 변경이 단골 원인)
```

## 6. SIGNALS-MAP 최종 갱신 (트랙 수료)

```
2절(수집·보존)을 완성하세요:
  로그:     Fluent Bit(fs버퍼) → Loki(라벨 소수)         ✅
  메트릭:   Prometheus(SM·relabel·rules)                ✅
  트레이스: OTel(주입·agent→gateway) → Tempo             ✅
  Events:  exporter → 로그 파이프라인                     ✅(05)
  상관:    derived fields·trace to logs·exemplar        ✅ ← 새 줄!
갱신 로그: "12 수료 — 오픈소스 풀스택 + 상관 완성. 다음: AWS 관리형(13~)"
```

## 7. 정리

```bash
kill %1 2>/dev/null || true
kind delete cluster --name correlate
rm -f /tmp/fb-loki.yaml
```

## 정리

- 배선 3종 완성: derived fields(로그→trace)·trace to logs(trace→로그, 라벨 매핑!)·exemplar(메트릭→trace)
- 클릭 완주: p99 ◆ → 간트(자식 없는 긴 부모=앱 내부) → 로그(pg_timeout) → 정량화 — 분 단위 조사
- 배선의 전제가 전부 앞 모듈의 규약이었습니다: trace_id 필드(02)·전파(04)·라벨 일관성(06·11)·histogram(03)
- 배선은 조용히 끊깁니다 — 체크리스트를 온보딩·변경 절차에
- **★ intermediate 수료: 신호가 흐르고, 울리고, 서로를 부릅니다 — 다음은 같은 그림을 AWS 부품으로(13~)**
