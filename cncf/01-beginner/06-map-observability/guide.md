# 학습 가이드 — 신호로 나누고, 파이프라인으로 잇습니다

## 이 지도의 좌표계 — 신호 × 단계

관측 카테고리의 로고 수십 개는 두 축으로 정리됩니다:

```
          수집(계측)          전송·가공           저장              질의·화면
메트릭    exporter/SDK   →   (Prometheus pull)  →  TSDB/Thanos   →  PromQL/Grafana
로그      앱 stdout      →   Fluent Bit/Fluentd →  Loki/ES/S3    →  LogQL/화면
트레이스  OTel SDK       →   OTel Collector     →  Jaeger/Tempo  →  Jaeger UI
```

어느 로고든 이 격자의 한두 칸입니다 — "Loki vs Prometheus"처럼 다른 행(신호)을 비교하거나, "OTel vs Jaeger"처럼 다른 열(수집 vs 저장)을 비교하는 것이 이 카테고리의 대표 혼동이고, 격자를 그리면 사라집니다. 03·04·05에서 반복한 "층 나누기"의 관측판입니다.

## 대통일 운동 — OpenTelemetry를 어디에 놓을 것인가

역사가 구조를 설명합니다: 메트릭은 Prometheus가, 로그는 Fluentd가, 트레이스는 OpenTracing/OpenCensus가 각자 표준을 만듭니다 — 트레이스 진영 둘이 합쳐 OpenTelemetry가 됐고, 이후 야심이 커졌습니다: **세 신호 전부의 계측 SDK·전송 프로토콜(OTLP)·수집기(Collector)를 통일**하겠다는 것. 지금의 실무 감각: 트레이스는 OTel이 기본값, 메트릭·로그는 기존 강자(Prometheus·Fluent Bit)와 공존하며 수렴 중.

중요한 경계 — OTel은 **수집·전송까지**입니다. 저장하지 않고 화면도 없습니다. "OTel 도입 = 관측 완성"이 아니라 "파이프라인의 앞단 표준화"이고, 뒷단(저장·질의)은 여전히 이 지도의 다른 주민들(Prometheus·Jaeger·Loki...)이 맡습니다. 이 경계를 아는 것이 이 지도의 최중요 문해력입니다.

## CNCF 지도의 경계 — 화면은 밖에 있습니다

실무 표준 조합 "Prometheus + Grafana"에서 Grafana는 CNCF가 아닙니다(Grafana Labs 소유, AGPL — 01의 라이선스 축). Loki(로그 저장)·Tempo(트레이스 저장)도 같은 회사입니다. 잘못이 아니라 **알고 선택할 일**입니다: 오픈소스지만 단일 벤더 소유이고, 라이선스와 상용 판(Grafana Cloud)의 경계를 채택 시 확인합니다 — 01의 소견서에서 "거버넌스" 항목이 CNCF 프로젝트와 다르게 채워집니다.

## eks 12~13과의 관계

CloudWatch(관리형)에서 배운 개념 — 계측, 로그 파이프라인, SLO, 알람 설계 — 이 그대로 이식됩니다. 다른 것은 운영 주체입니다: 여기의 스택은 우리가 띄우고 우리가 스케일합니다(특히 Prometheus의 카디널리티와 장기 저장이 운영 무게의 중심 — 심층 11에서). 지도 단계에서는 "무엇이 어느 칸인가"까지, 운영의 무게는 심층에서.
