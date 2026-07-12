# Lab 02 — 게임데이: 모의 장애 리허설 (파트의 실기 시험)

> 이 파트에서 지은 전부를 실전 형식으로 시험합니다 — 결함을 주입하고, 알림이 울리고, runbook을 따라 완화하고, 타임라인을 기록하고, 미니 포스트모템까지. 혼자 실습이라도 역할(IC·조사·서기)을 의식적으로 전환하며 밟습니다.

## 0. 준비 (lab-01 이어서 — 스택·runbook·타임라인 템플릿)

```bash
# 관찰자용 스톱워치 준비 — 각 단계 시각을 기록합니다
date "+게임데이 시작: %T"
```

## 1. 시나리오 주입 — "나쁜 배포" (관찰자 역할)

시나리오는 참가자에게 비밀이지만, 혼자 실습이므로 "주입하는 나"와 "대응하는 나"를 분리합니다:

```bash
# 나쁜 배포: 에러를 뿜는 버전으로 교체 (21의 에러 경로를 트래픽으로)
kubectl -n shop set env deploy/payment BAD_RELEASE=true   # 배포 이벤트 생성(마커!)
kubectl -n shop rollout status deploy/payment

# 에러 트래픽 시작 (BAD_RELEASE의 효과 흉내 — 예제 앱이라 /err로 대체)
kubectl -n shop run bad-traffic --image=curlimages/curl --restart=Never -- sh -c '
  while true; do curl -s http://payment:8080/err >/dev/null; curl -s http://payment:8080/ >/dev/null; sleep 0.1; done'
date "+주입 완료: %T"
# 여기서부터 "대응하는 나"로 전환 — 알림이 올 때까지 대기 (보지 말 것!)
```

## 2. 감지 — 알림이 울리는가 (측정 ①)

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
sleep 3
# 번레이트 진행 관찰 (실전이면 페이저가 울림 — 10 lab-02의 웹훅)
watch -n 30 'curl -s localhost:9090/api/v1/alerts | grep -o "\"alertname\":\"[^\"]*\"\|\"state\":\"[a-z]*\"" | paste - -'
# PaymentBudgetFastBurn pending → firing
date "+감지(firing): %T"     # 측정 ①: 주입→감지 시간
```

**판정** — 울리지 않으면 그 자체가 최대 발견입니다(10·21의 구멍: 임계? 창? 라우팅?). 게임데이의 절반은 "안 울리는 알림"과 "안 이어지는 링크"를 찾는 것입니다.

## 3. 대응 — runbook을 따라 (역할 전환 명시)

```
[서기 모자] 타임라인 기록 시작 (lab-01 템플릿)
[IC 모자] 심각도 판정: fast burn = SEV2 (theory 3절의 숫자 기준)
[조사 모자] runbook의 "즉시 확인" 3개를 순서대로:
```

```bash
# runbook 즉시-1: L1 — payment 에러율 (실습은 쿼리로 대신)
curl -s 'localhost:9090/api/v1/query?query=slo:payment_error_ratio:rate5m' | grep -o '"value":\[[^]]*\]'
# ~0.5 — 사용자 절반이 실패 중. 범위 확인.

# runbook 즉시-2: 최근 배포? ★
kubectl -n shop rollout history deploy/payment | tail -3
# REVISION N — 방금(주입 시각)의 배포 발견!
date "+원인 후보(배포) 도달: %T"    # 측정 ③

# runbook 즉시-3: 범위 — 전체 Pod인가
curl -s 'localhost:9090/api/v1/query?query=sum%20by%20(pod)%20(rate(http_requests_total{namespace="shop",code=~"5.."}[5m]))' | head -c 300
# 전체 — "특정 Pod" 조건 아님
```

```bash
# [IC 모자] 완화 결정: runbook 표의 1행 조건 충족(최근 배포) → 롤백 승인
# [조사 모자] 완화 실행:
kubectl -n shop rollout undo deploy/payment
kubectl -n shop rollout status deploy/payment
kubectl -n shop delete pod bad-traffic --force --grace-period=0   # (주입 중단 = 효과 확인을 위해)
date "+완화 실행: %T"    # 측정 ④
```

## 4. 회복 확인과 해소

```bash
sleep 300
curl -s 'localhost:9090/api/v1/query?query=slo:payment_error_ratio:rate5m' | grep -o '"value":\[[^]]*\]'
# ~0.02로 회복 (baseline 수준)
curl -s localhost:9090/api/v1/alerts | grep -c firing || echo "0"
# FastBurn resolve (keep_firing_for 후)
date "+해소 확인: %T"
# [IC 모자] 해소 선언 → [서기] 타임라인 마감
```

## 5. 측정 집계와 미니 포스트모템

```
측정 결과 (타임라인에서):
  주입→감지: __분 (알림 체계의 품질 — 21의 창·for 설계 검증)
  감지→원인 후보: __분 (runbook 즉시-2가 배포를 짚음 — 마커·history의 힘)
  원인 후보→완화: __분 (롤백 리허설(lab-01)의 보상)
  총 MTTR: __분

미니 포스트모템 (theory 5절 구조로 — 30분):
  잘된 것: runbook 표의 조건 매칭이 즉답 / 롤백이 준비돼 있었습니다
  구멍 (게임데이의 수확 — 예시):
    - L1 링크가 uid 변경으로 404였다면 → 09의 링크 무결성 액션
    - "특정 Pod" 쿼리가 runbook에서 오타였다면 → 그 자리에서 수정 커밋
    - 감지가 느렸다면 → 21의 창·임계 재검토
  액션: runbook 수정(즉시)·배선 수정·다음 게임데이 시나리오에 반영
```

**이 파트의 실기 시험으로서** — 오늘 밟은 사슬을 되짚어 보라: 알림(10·21) → 착지(09) → 조사(05의 반사·08의 쿼리) → 배포 마커(09) → 롤백(완화 우선) → 타임라인(서기) → 포스트모템. **파트의 모든 모듈이 이 15분 안에 있었습니다.** 게임데이가 매끄러웠다면 파트를 체화한 것이고, 막힌 곳이 복습 목록입니다.

## 6. 확장 시나리오 (다음 게임데이들)

```
이 파트의 pitfalls가 시나리오 보고입니다:
  "조용한 미수집" (08) — SM 라벨을 몰래 떼고: absent 알림이 잡는가요?
  "로그 폭주" (02) — flooder 주입: 볼륨 알림(22)과 수문이 작동하는가요?
  "카디널리티 폭발" (03) — 나쁜 라벨 배포: sampleLimit·급증 알림?
  "수집기 유실" (06) — 목적지 차단: dropped 알림과 fs 버퍼?
  "알림 체계의 죽음" (14) — 워치독이 끊기면 누가 아는가요?
→ 분기마다 하나씩 — 그리고 신규 입사자 온보딩과 결합
```

## 7. 정리

```bash
kill %1 2>/dev/null || true
kind delete cluster --name incident
rm -rf runbooks
```

## 정리

- 게임데이의 절반은 "안 울리는 알림·안 이어지는 링크" 찾기 — 구멍이 수확입니다
- 측정 4구간(감지·착지·원인 후보·완화)이 개선의 좌표 — 감으로 하지 않습니다
- 역할 모자의 명시적 전환(IC는 조사하지 않습니다)을 혼자 실습에서도 훈련
- runbook의 조건→조치 표가 결정을 3분으로 — 완화 우선(롤백)이 작동함을 확인
- **★ 파트의 실기 시험: 15분의 사슬에 모든 모듈이 있었습니다 — 막힌 곳이 복습 목록입니다**
