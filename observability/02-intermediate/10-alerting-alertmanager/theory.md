# 이론 — 좋은 알림, 규칙 문법, 라우팅 트리, 그룹핑·억제·사일런스, 피로 관리

> **🌱 17세 눈높이 비유: 학교 방송실의 방송 규칙**
> - **나쁜 방송실** = 사소한 일마다 전교 방송("3반 지우개 분실") → 다들 방송을 무시 → 진짜 화재 방송도 흘려들음 (알림 피로)
> - **울릴 자격 심사** = 방송 기준: 학생이 실제로 영향받는 일(증상)만, 들은 사람이 할 행동이 있게, 긴급하면 즉시·아니면 종례 때(심각도)
> - **for(지속 확인)** = 연기가 3초 보였다고 방송하지 않습니다 — 몇 분 지속되는지 확인 후
> - **라우팅 트리** = 방송 대상 분기: 체육 관련은 체육부장에게만, 화재는 전교+소방서
> - **그룹핑** = 같은 화재로 감지기 50개가 울려도 방송은 한 번 ("3층 화재")
> - **억제** = "화재 발생" 방송 중엔 "3층 온도 높음" 방송은 생략 (원인이 이미 공지됨)
> - **사일런스** = 소방 훈련 시간엔 감지기 방송 임시 꺼둠 (기한 필수!)

---

## 1. 좋은 알림의 3심사 (guide 요약)

```
① 증상 기반: 사용자 영향(RED — 에러율·지연·가용성)에 page를
   원인(USE·내부 상태)은 조사용 대시보드·ticket으로
② 행동 가능: runbook + 대시보드 링크 필수 (다음 행동이 명시)
③ 긴급성 구분: page(깨울 일) vs ticket(아침에 볼 일)
   → severity 라벨로 명시하고 라우팅이 이를 소비
```

## 2. 알림 규칙 문법 (PrometheusRule)

```yaml
groups:
  - name: payment.alerts
    rules:
      - alert: PaymentHighErrorRate
        expr: service:http_error_ratio:rate5m{service="payment"} > 0.05
        for: 5m                        # 지속 조건 (순간 스파이크 필터)
        keep_firing_for: 5m            # 회복 후에도 잠시 유지 (플래핑 방지)
        labels:
          severity: page               # 라우팅의 키
          team: commerce
        annotations:
          summary: "payment 에러율 {{ $value | humanizePercentage }} (5분 지속)"
          dashboard: "https://grafana.example/d/svc-red?var-service=payment"
          runbook: "https://runbooks.example/payment-errors"

핵심 요소:
  expr — ★ recording rule 위에 (08의 단일 정의 — 대시보드와 같은 세계)
  for — 지속 시간 (심각도별: page 5m, ticket 30m~)
  keep_firing_for — 경계 근처 진동(플래핑)으로 인한 resolve/fire 반복 방지
  labels — severity·team (라우팅 재료)
  annotations — 사람용: 요약(값 포함)·대시보드(09 착지)·runbook(23)

상태 흐름: inactive → pending(조건 참, for 대기) → firing
```

## 3. 실전 패턴 모음

```
증상(RED) 알림:
  에러율: service:http_error_ratio:rate5m > 0.05
  지연: service:http_p99:5m > 1.5 (SLO 경계 기반 — 21)
  트래픽 소실: rate(...) < 정상 하한 (0이 된 것도 이상!)

"없음"의 감지 (조용한 실패 방지 — 08):
  absent(up{job="payment"})       — 타깃 자체가 사라짐
  up == 0                          — 스크레이프 실패
  absent(service:...:rate5m)       — recording rule이 안 돎

플랫폼 알림 (Events·KSM 기반 — 05):
  increase(kube_pod_container_status_restarts_total[1h]) > 3   — 재시작 반복
  kube_pod_status_phase{phase="Pending"} > 0 (for 15m)         — 스케줄 불능 지속
  predict_linear(node_filesystem_avail_bytes[6h], 4*3600) < 0  — 디스크 고갈 예측(ticket!)

파이프라인 자기 감시 (06·08):
  rate(fluentbit_output_dropped_records_total[5m]) > 0          — 로그 유실 발생
  prometheus_tsdb_head_series > 한도                             — 카디널리티 팽창

안티패턴:
  인스턴스별 알림 (Pod 교체마다 리셋 — 08 사고) → 서비스 집계 위에
  원인 나열 (CPU·메모리·스레드 각각 page) → 증상 하나 + 조사 대시보드
```

## 4. Alertmanager 라우팅 트리

```yaml
route:                          # 루트
  receiver: default-slack       # 매칭 안 되면 여기로
  group_by: [alertname, service]
  group_wait: 30s               # 첫 통지 전 모아 기다림 (묶음 형성)
  group_interval: 5m            # 같은 그룹의 추가 알림 통지 간격
  repeat_interval: 4h           # 미해결 반복 알림 간격
  routes:
    - matchers: [severity="page"]
      receiver: pagerduty       # 깨울 일은 페이저로
      continue: false
    - matchers: [team="commerce"]
      receiver: commerce-slack  # 팀 라우팅
    - matchers: [alertname=~"Info.*"]
      receiver: "null"          # 정보성은 버림 (아예 안 만드는 게 더 좋지만)

동작: 트리를 위에서 매칭 — 첫 일치 수신자(continue로 계속 탐색 가능)
설계 원칙: severity가 1차 분기(page/ticket), team이 2차 (수신자 소유권)
```

## 5. 그룹핑·억제·사일런스 — 폭풍 통제 3종

```
그룹핑 (group_by):
  노드 하나가 죽으면 그 위 Pod 알림 수십 개 발화
  → group_by: [alertname]으로 "PodDown ×37" 한 통으로
  → group_wait 동안 모아서 묶음 완성 후 발송

억제 (inhibit_rules):
  - source_matchers: [alertname="NodeDown"]     # 이게 발화 중이면
    target_matchers: [alertname="PodDown"]      # 이것들은 침묵
    equal: [node]                               # 같은 node 라벨일 때만
  → 원인(노드 다운)이 울리면 증상(그 노드 Pod들)은 소거
  → 계층 알림 설계: 상위가 하위를 덮습니다

사일런스:
  계획 작업(배포·마이그레이션) 중 매처 기반 임시 소거
  ★ 반드시 기한 설정 — "영구 사일런스"는 알림 삭제와 같습니다 (몰래 썩습니다)
  만든 사람·사유 기록 (누가 왜 껐는지)
```

## 6. 알림 피로 관리 — 운영 루프

```
측정: 주간 알림 통계 — 팀별 page 수·ACK 시간·행동 없이 닫힌 비율
리뷰: 온콜 회고에서 "이번 주 알림 중 무의미했던 것" 지목
조치의 우선순위:
  행동 없이 닫힌 알림 → 삭제 또는 ticket로 강등 (삭제의 용기!)
  중복·연쇄 → 그룹핑·억제 추가
  플래핑 → for·keep_firing_for·임계 조정
목표 감각: 온콜 1교대당 page 소수 — 그 이상이면 사람이 아니라
  체계가 고장난 것 (23의 온콜 설계)

★ 알림 규칙도 코드 (PrometheusRule → GitOps) — 추가·삭제가 PR 리뷰를
  거치게: "울릴 자격" 심사를 리뷰 절차로
```

## 7. 소스/도구에서 확인하기

- Alertmanager 문서: prometheus.io/docs/alerting — route·inhibit·silence
- kube-prometheus-stack 기본 알림 세트 (좋은 예시 — 뜯어보기)
- Rob Ewaschuk "My Philosophy on Alerting" (증상 기반 알림의 고전)
- 21(SLO 번레이트 — 이 규율의 고급판)·23(온콜)

## 요약 카드

| 질문 | 답 |
|------|----|
| 울릴 자격 3심사? | 증상 기반(사용자 영향)·행동 가능(runbook·대시보드)·긴급성(page/ticket) |
| for의 역할? | 지속 확인 — 순간 스파이크 필터 (keep_firing_for는 플래핑 방지) |
| 알림은 어디에 걸까요? | recording rule 위에(정의 단일화)·서비스 집계 위에(인스턴스 X) |
| "없음" 감지? | absent(up)·up==0·absent(rule) — 조용한 실패를 시끄럽게 |
| 라우팅 설계? | severity 1차(page/ticket)·team 2차 — 트리 매칭 |
| 폭풍 통제 3종? | 그룹핑(묶음)·억제(원인이 증상 덮음)·사일런스(기한 필수) |
| 피로 관리? | 주간 통계→회고→삭제의 용기 — 행동 없는 알림은 부채 |
| 알림도 코드? | PrometheusRule + GitOps — 추가·삭제가 PR 심사를 거치게 |
