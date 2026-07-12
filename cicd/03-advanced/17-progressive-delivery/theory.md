# 이론 — Rollout 구조, 자동 분석, 트래픽, 지표 설계

> **🌱 17세 눈높이 비유: 자동 시식 코너**
> 새 메뉴(신버전)를 출시하는데:
> - **11의 수동 카나리** = 요리사가 손님 5명에게 시식시키고 **직접 표정을 관찰**해 판단
> - **17의 자동 카나리** = 시식대에 센서(메트릭)를 달아, 손님 5명의 만족도(오류율·지연)를 **자동 측정** → 좋으면 더 많은 손님에게, 나쁘면 자동으로 옛 메뉴로 되돌림
> - **AnalysisTemplate** = 센서가 무엇을 측정할지(만족도 90% 이상?) 정의
> - **자동 롤백** = 만족도가 기준 미달이면 요리사를 부르지 않고 즉시 옛 메뉴로
> - 핵심: **센서(지표)가 잘못 설정되면** 맛없는 메뉴가 통과하거나 맛있는 메뉴가 막힙니다

---

## 1. Argo Rollouts 구조 — Deployment의 진화

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout                      # Deployment 대체 (카나리/블루그린 네이티브)
spec:
  replicas: 10
  strategy:
    canary:
      steps:
        - setWeight: 5             # 5% 트래픽
        - pause: { duration: 2m }  # 관찰 (또는 분석)
        - setWeight: 25
        - pause: {}                # 무한 — 수동 승격 대기
        - setWeight: 50
        - analysis:                # ★ 자동 분석 (§2)
            templates: [{ templateName: success-rate }]
        - setWeight: 100
      trafficRouting:              # eks 14/20의 트래픽 관리
        alb: {} # 또는 istio, smi, nginx
```

Deployment(11의 롤링)와의 차이: Rollout은 **카나리/블루그린을 네이티브로, 단계별 트래픽 가중치와 분석**을 갖습니다. 11에서 replica 조작으로 흉내 낸 것이 1급 기능이 됐습니다.

## 2. AnalysisTemplate — 지표가 게이트

```yaml
kind: AnalysisTemplate
metadata: { name: success-rate }
spec:
  metrics:
    - name: success-rate
      interval: 1m
      successCondition: result >= 0.95        # ★ 성공률 95% 이상
      failureLimit: 3                          # 3번 실패하면 롤백
      provider:
        prometheus:                            # eks 15의 Prometheus
          address: http://prometheus.monitoring:9090
          query: |
            sum(rate(http_requests_total{status!~"5..",canary="true"}[2m]))
            / sum(rate(http_requests_total{canary="true"}[2m]))
```

이것이 11의 "지표 없는 카나리는 느린 배포"에 대한 답입니다:

```
카나리 5% 배포 → AnalysisRun이 매분 Prometheus 쿼리 → 성공률 계산
  ≥ 0.95: 다음 step으로 (자동 확대)
  < 0.95 (3회): 자동 롤백 (사람 없이)
```

**사람의 판단이 successCondition으로 코드화**됐습니다. eks 13의 SLI(오류율·p99)가 여기서 배포 게이트가 됩니다.

## 3. 분석의 종류와 타이밍

| 타입 | 언제 | 예 |
|------|------|----|
| **배경 분석**(background) | 롤아웃 내내 | 전 구간 오류율 감시 |
| **인라인 분석**(step) | 특정 step에서 | 50%에서 5분 분석 |
| **사전 분석**(prePromotion) | 트래픽 주기 전 | 스모크 테스트 |
| **사후 분석**(postPromotion) | 100% 후 | 최종 검증 |

11의 CodeDeploy 훅(BeforeAllowTraffic/AfterAllowTraffic)에 대응 — 그러나 Rollouts는 **메트릭 쿼리를 반복**하며 지속 판단한다는 점이 더 강력합니다.

## 4. 트래픽 관리 — eks 14/20의 결합

Rollouts는 자체로 트래픽을 못 나눕니다 — **트래픽 제공자**와 결합합니다:

| 제공자 | 방식 | 배운 곳 |
|--------|------|--------|
| ALB | 타깃 그룹 가중치 | eks 14 |
| Istio | VirtualService 가중치 | eks 20 |
| SMI/NGINX/기타 | 각자 방식 | |
| (없음) | replica 비율(근사) | 11의 그 방법 |

정밀한 % 트래픽 분할은 트래픽 제공자가 있어야 합니다(replica 비율은 근사 — 11 lab-01의 한계). eks 14에서 ALB 가중치를, 20에서 메시 분할을 배운 것이 여기서 Rollouts의 하부가 됩니다.

## 5. 자동 롤백 — 초 단위 복구

```
분석 실패 감지 → Rollout이 트래픽을 stable(구버전)로 100% 복귀 → 카나리 ReplicaSet 폐기
```

11의 "롤백 속도 계층"에서 카나리는 초 단위(가중치 0)였는데, Rollouts는 이것을 **자동**으로 합니다. 사람이 알람을 보고 반응하는 시간(수 분~수십 분)이 제거됩니다 — 01 DORA의 복구 시간(MTTR)이 극적으로 줍니다.

## 6. 지표 설계 — 자동화의 품질

progressive delivery의 성패는 도구가 아니라 **지표 설계**입니다:

```
좋은 지표:
  - 사용자 영향 직결 (성공률, p99 지연 — eks 13)
  - 카나리와 stable을 비교 (절대값 아닌 상대 — 배포 무관 변동 배제)
  - 충분한 트래픽 (5%가 통계적으로 의미 있을 만큼)

나쁜 지표(함정):
  - 배포와 무관한 것 (CPU — 15의 교훈)
  - 느린 지표 (5분 집계면 카나리가 이미 확대됨)
  - 단일 지표 (성공률만 보면 지연 폭발을 놓침)
  - 트래픽 부족 (5%가 초당 1요청이면 통계 무의미)
```

11의 사고 사례(세션 파싱 실패가 4xx라 5xx 지표에 안 걸림)가 여기서 재현됩니다 — **무엇을 측정하지 않느냐**가 자동화의 사각입니다.

## 7. Flagger 비교

| | Argo Rollouts | Flagger |
|---|---|---|
| 생태계 | ArgoCD(14) | Flux(15) |
| 대상 | Rollout CRD(Deployment 대체) | 기존 Deployment에 얹음 |
| 분석 | AnalysisTemplate | MetricTemplate |
| UI | Argo 대시보드 | (Flux/Grafana) |

접근 차이: Rollouts는 Deployment를 Rollout으로 교체, Flagger는 Canary CRD로 기존 Deployment를 감쌉니다. 14/15의 GitOps 도구 선택과 짝지어 고르는 경우가 많습니다.

## 8. 소스/도구에서 확인하기

- Argo Rollouts: https://github.com/argoproj/argo-rollouts (CNCF)
- Flagger: https://github.com/fluxcd/flagger
- AnalysisTemplate 예제: rollouts docs "Analysis"
- eks 13(SLI 측정), 15(Prometheus) — 지표의 원천

## 요약 카드

| 질문 | 답 |
|------|----|
| 무엇의 합류? | 11(카나리)+14(GitOps)+eks13(SLI)+eks15(메트릭) |
| Rollout이 Deployment와 다른 점? | 카나리/블루그린 네이티브 + 단계별 트래픽 + 분석 |
| 지표가 게이트? | AnalysisTemplate.successCondition — 사람 판단의 코드화 |
| 트래픽 분할? | 트래픽 제공자 결합(ALB eks14 / Istio eks20) |
| 자동 롤백 속도? | 초 단위(가중치 복귀) — MTTR 급감 |
| 성패를 정하는 것? | **지표 설계**(도구 아님) — 무엇을 측정 안 하느냐가 사각 |
| Flagger와 차이? | Rollout 교체(Argo) vs Deployment에 얹음(Flux) |
