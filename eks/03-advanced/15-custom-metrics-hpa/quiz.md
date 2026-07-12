# 자가 점검 퀴즈

**Q1.** CPU 기반 스케일링이 실패하는 두 시나리오를 들고, RPS 기반이 그것을 어떻게 피하는지 설명하세요.

**Q2.** 메트릭 API 3형제와 각각의 서빙 주체·HPA 문법(type)을 매핑하세요.

**Q3.** Prometheus Adapter 규칙의 세 요소(seriesQuery/metricsQuery/name)가 각각 답하는 질문은?

**Q4.** 앱은 "누적 카운터"를 내는데 HPA는 "초당 요청"이 필요합니다 — 이 간극을 누가 어떻게 메우나요?

**Q5.** HPA target(averageValue)을 산정하는 공식과 각 항의 출처는? "×0.7"의 존재 이유는?

**Q6.** KEDA와 HPA의 관계를 정확히 서술하고, scale-to-zero에서 0→1과 1→N의 담당이 각각 누구인지 밝혀라.

**Q7.** HTTP 서비스에 minReplicaCount: 0이 위험한 두 가지 이유(요청 관점 + 메트릭 관점)는?

**Q8.** Prometheus가 죽었을 때 RPS HPA의 동작과, 이 위험에 대한 방어 3가지는?

---

## 정답

**A1.** ① 급증 트래픽: CPU는 유입의 **결과**라 오를 때쯤엔 이미 큐가 자라 있습니다(후행). ② IO-bound 앱: DB/외부 API 대기로 죽어가도 CPU는 한가합니다(간접). RPS는 유입 **원인**을 직접 보므로 빠르고, 병목 종류와 무관하게 유효합니다.

**A2.** metrics.k8s.io ← metrics-server (type: Resource). custom.metrics.k8s.io ← Prometheus Adapter 등 (type: Pods/Object). external.metrics.k8s.io ← KEDA 등 (type: External). 셋 다 aggregated API라 `kubectl get --raw`로 직접 조회 가능.

**A3.** seriesQuery: "Prometheus의 **어떤 시계열**을 재료로?" metricsQuery: "**어떻게 가공**해?(rate 창 포함)" name: "메트릭 API에 **무슨 이름**으로 걸어?" — HPA는 그 이름만 압니다.

**A4.** 어댑터(또는 KEDA 스케일러)의 metricsQuery가 `rate(counter[1m])`로 **시간당 미분**을 계산합니다 — 누적값의 기울기가 곧 RPS. rate 창(1m)이 반응성과 노이즈의 트레이드오프 손잡입니다.

**A5.** target = (무릎 rps ÷ 측정 시 replicas) × 0.7. 무릎과 replicas는 13의 부하 측정 보고서에서. ×0.7 = 반응 지연(메트릭 30~60s + Pod 기동)을 흡수하는 쿠션 — 그 시간 동안 기존 Pod가 무릎을 넘지 않게 하는 여유분.

**A6.** KEDA는 HPA의 포장 — ScaledObject를 읽어 **HPA를 생성·관리**하고 자신은 external 메트릭 서버 역할. 0→1은 HPA가 못 하므로 KEDA 자신이(activation), 1→N의 산수는 생성된 HPA가 수행합니다.

**A7.** ① 요청 관점: Pod 0 = 엔드포인트 0 — 첫 요청이 실패합니다(잡아둘 프록시가 없습니다). ② 메트릭 관점: 트리거가 앱 메트릭이면 생산자가 0명이라 **깨어날 신호 자체가 소멸**(닭-달걀). 그래서 0은 일감이 Pod 밖(큐/cron)에 쌓이는 워크로드의 특권.

**A8.** 메트릭 unknown → HPA는 대개 현 replicas로 **동결**(스케일 판단 중지). 방어: ① 같은 HPA에 CPU 메트릭 병기(HPA는 메트릭들 중 최대 replicas 채택 — 최후 안전망) ② 메트릭 파이프라인을 모니터링·SLO 대상으로(12) ③ minReplicas를 기본 트래픽 감당선으로 + 수동 override runbook.
