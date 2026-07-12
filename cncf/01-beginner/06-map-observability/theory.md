# 이론 — 세 신호의 분업, 신호×단계 격자 전수 지도, OTel의 경계

> **🌱 17세 눈높이 비유: 학교 보건실의 세 기록**
> - **메트릭** = 체온계 그래프 — 숫자의 추이. "열이 있다"(무엇이 이상한가)를 가장 싸고 빠르게
> - **로그** = 문진 기록 — "오늘 아침부터 목이 아프고..." 서술형. "왜"의 단서가 여기에
> - **트레이스** = 동선 추적 — 급식실→3반→체육관. 여러 곳(서비스)을 지나는 사건의 "어디서"를
> - 세 기록은 **같은 사건의 세 관점** — 체온(메트릭)으로 이상을 알고, 동선(트레이스)으로 위치를 좁히고, 문진(로그)으로 원인을 읽습니다
> - **OpenTelemetry** = 기록 양식·제출함의 표준화 — 어느 반이든 같은 양식으로 써서 같은 함에 넣게. 단, **보관실과 열람실은 따로**(저장·화면은 OTel이 아닙니다)
> - **Collector** = 보건실 접수대 — 양식을 받아 분류·가공해 각 보관실로 배분

---

## 1. 세 신호의 분업 — 비용과 답의 종류가 다릅니다

| 신호 | 답하는 질문 | 비용 특성 | 대표 함정 |
|---|---|---|---|
| 메트릭 | **무엇이** 이상한가 (추이·비율) | 저렴·집계 가능 — 상시 전수 | 카디널리티 폭발(라벨 남용) |
| 로그 | **왜** (그 순간의 서술) | 볼륨 비쌈 — 보존·검색이 돈 | 구조화 안 된 로그(grep 지옥) |
| 트레이스 | **어디서** (요청의 경로·구간별 시간) | 계측 필요 — 샘플링으로 통제 | 전파 끊김(컨텍스트 유실) |

운영 문법(eks 12~13의 복습): 알람은 메트릭으로(SLO), 조사는 트레이스로 좁혀 로그로 읽습니다 — 신호 하나로 전부를 하려는 순간 비용이나 사각이 옵니다.

## 2. 전수 지도 — 신호×단계 격자 (기준 시점 2026-06)

### 메트릭 행

| 프로젝트 | 성숙도 | 칸 | 한 줄 |
|---|---|---|---|
| **Prometheus** | Graduated (2호!) | 수집+저장+질의 | pull 스크레이프·TSDB·PromQL — 사실상 메트릭의 표준 (심층 11) |
| **Thanos** | Incubating | 장기 저장·전역 질의 | Prometheus들 위에 S3 장기 보존 + 전역 뷰 |
| Cortex→**Mimir** | (Grafana — 비CNCF화) | 장기 저장(멀티테넌트) | Cortex(CNCF)의 후계가 회사 밖으로 — 지도의 이동 사례 |
| VictoriaMetrics | (비CNCF) | 대체 TSDB | 성능 지향 대안 |
| OpenMetrics | (Prometheus로 흡수) | 노출 형식 표준 | 표준이 본가로 합쳐진 사례 |

### 로그 행

| 프로젝트 | 성숙도 | 칸 | 한 줄 |
|---|---|---|---|
| **Fluentd** | Graduated | 전송·가공 | 루비 기반 원조 — 플러그인 바다 |
| **Fluent Bit** | (Fluentd 서브) | 전송·가공(경량) | C 기반 — 노드 에이전트의 실무 기본값 (eks 12의 그것) |
| Loki | (Grafana — 비CNCF) | 저장·질의 | "라벨만 인덱싱"의 저비용 노선 — Grafana 세트 |
| Elasticsearch/OpenSearch | (외부/LF) | 저장·질의 | 전문 검색 노선 — 비용 무게급 |

### 트레이스 행

| 프로젝트 | 성숙도 | 칸 | 한 줄 |
|---|---|---|---|
| **Jaeger** | Graduated | 저장·질의·UI | 트레이스 백엔드의 표준격 (심층 13) — 수집은 OTel로 위임하는 흐름 |
| Zipkin | (외부) | 저장·UI | 원조 — 레거시 호환의 이름 |
| Tempo | (Grafana — 비CNCF) | 저장 | 오브젝트 스토리지 직결의 저비용 노선 |

### 통일 운동 — 신호를 관통하는 열

| 프로젝트 | 성숙도 | 한 줄 |
|---|---|---|
| **OpenTelemetry** | Incubating (규모는 K8s 다음) | **계측 SDK + OTLP 프로토콜 + Collector** — 세 신호의 수집·전송 표준. 저장·화면은 안 함 (심층 12) |

### 화면·기타

```
Grafana (비CNCF·AGPL) — 사실상의 표준 화면. 단일 벤더 소유임을 알고 채택 (01의 소견 축 조정)
기타 주민: Pixie(eBPF 자동 계측 — 04와 연결), OpenCost(비용 관측), 
          Prometheus 생태의 exporter 군단(node/kube-state-metrics — k8s에서 사용한 것들)
```

## 3. OpenTelemetry의 경계 — 최중요 문해력

```
OTel이 하는 것                          OTel이 안 하는 것
├ 계측 SDK (언어별 — 자동 계측 포함)     ├ 저장 (TSDB·로그 저장소·트레이스 백엔드 없음)
├ OTLP (신호 공통 전송 프로토콜)         ├ 질의 언어·알람
└ Collector (수신→가공→내보내기)         └ 대시보드·UI

Collector 파이프라인 (lab-02의 실물):
  receivers(otlp, prometheus...) → processors(batch, filter, 샘플링...) → exporters(jaeger, prometheus, loki...)
  = 관측의 "게이트웨이" — 백엔드 교체가 exporter 한 줄 (수집 재계측 불필요!)
```

Collector의 전략적 의미: **계측(앱 코드)과 백엔드(저장소 선택)의 디커플링** — 백엔드를 Jaeger에서 Tempo로, 자체에서 SaaS로 바꿔도 앱은 그대로입니다. 05의 CSI가 스토리지에서 한 일을 관측에서 합니다.

## 4. 지도의 역학 — 세 가지 흐름

```
① 수렴: 수집·전송은 OTel로 (트레이스는 완료, 메트릭·로그는 진행 중 — Prometheus도 OTLP 수용)
② 분화: 저장은 규모별로 (단일 Prometheus → Thanos/Mimir 장기·전역 / 로그도 ES → Loki 저비용 분화)
③ 이탈과 흡수: Cortex→Mimir(회사로), OpenMetrics→Prometheus(본가로) — 지도는 움직입니다 (01)
```

## 5. 스택 조합의 전형 (지도 수준 — 상세 설계는 심층·46에서)

```
자체 운영 표준형: OTel SDK/Collector + Prometheus(+Thanos) + Fluent Bit + Loki 또는 ES + Jaeger + Grafana
관리형 혼합형:   OTel Collector에서 CloudWatch/X-Ray로 (eks 12의 세계와 연결 — Collector가 스위치)
판단 축: 운영 여력(카디널리티·저장 스케일 운영은 실전 무게) vs 비용 통제(관리형 프리미엄)
```

## 6. 소스/도구에서 확인하기

- Prometheus: https://prometheus.io/docs — data model·PromQL / Thanos: https://thanos.io
- OpenTelemetry: https://opentelemetry.io/docs — Collector·OTLP·시맨틱 컨벤션
- Jaeger: https://www.jaegertracing.io / Fluent Bit: https://fluentbit.io
- 성숙도 재확인: lab-01 (landscape.yml)

## 요약 카드

| 질문 | 답 |
|------|----|
| 좌표계? | 신호(메트릭/로그/트레이스) × 단계(수집/전송/저장/질의) 격자 — 다른 행·열 비교가 대표 혼동 |
| 세 신호의 분업? | 무엇이(메트릭·알람) / 어디서(트레이스·좁히기) / 왜(로그·읽기) |
| OTel의 경계? | 수집·전송(SDK·OTLP·Collector)까지 — 저장·질의·화면은 다른 주민들 |
| Collector의 의미? | 계측과 백엔드의 디커플링 — 백엔드 교체가 exporter 한 줄 (관측의 CSI) |
| 장기 저장 분화? | Prometheus 단일 → Thanos(S3 장기·전역 뷰)/Mimir — 규모가 만든 카테고리 |
| CNCF 밖 주민? | Grafana·Loki·Tempo(한 회사·AGPL) — 알고 선택 (01의 소견 축) |
