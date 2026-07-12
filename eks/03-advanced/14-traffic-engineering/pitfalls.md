# 흔한 함정 5선

## 1. Ingress를 지우지 않고 퇴근

이 파트 최다 과금 사고. Ingress 하나 = ALB 하나 = **시간당 과금 + LCU**가 조용히 돕니다. 실험용 Ingress는 세션 종료 전 반드시 삭제하고, `aws elbv2 describe-load-balancers`로 소멸까지 확인(컨트롤러가 지워주지 못하는 경우 — finalizer 꼬임, 컨트롤러 죽음 — 가 있습니다). 팀 규칙으로는 태그 기반 주기 스캔이 안전망.

## 2. keep-alive 부등식 역전 — "가끔 나는 502"

앱의 keep-alive idle(예: Node.js 기본 5s)이 ALB idle(60s)보다 짧으면, ALB가 재사용하려는 순간 앱이 먼저 끊는 race로 **간헐 502**가 납니다. 트래픽이 많을수록, 요청 간격이 애매할수록 잦습니다. 재현이 안 돼 미스터리로 남기 쉽지만 수정은 한 줄(앱 keep-alive를 65s+)입니다. 배포 시각과 무관한 502라면 이것부터.

## 3. target-type ip인데 readiness gate 없이 배포

08의 ip 모드는 ALB가 Pod를 **직접** 타깃으로 잡습니다 — 그래서 k8s의 Ready와 ALB의 healthy가 따로 노는 순간이 그대로 유저 오류가 됩니다. ns 라벨 한 줄(`pod-readiness-gate-inject=enabled`)로 두 시계를 묶을 수 있는데도 빠뜨려서 "배포 때마다 3초 5xx"를 안고 사는 팀이 많습니다. lab-02의 대조군이 그 팀의 매일입니다.

## 4. deregistration_delay 300초 방치 — 또는 preStop과의 부정합

기본 300s를 그대로 두면 replicas 10짜리 배포가 draining 대기로 수십 분이 됩니다. 반대로 deregistration을 조여도 **preStop 없이** Pod가 즉사하면 전파 지연 동안 502입니다. 둘은 세트입니다: preStop sleep(전파 시간) + deregistration(최장 요청 시간) — 각자의 근거 숫자를 갖고 정해야 하며, "그냥 크게"도 "그냥 작게"도 사고입니다.

## 5. 헬스체크를 비싼 경로에

TG 헬스체크 경로를 DB까지 두드리는 `/`나 `/api/health-full`로 잡으면 — 타깃 수 × 주기만큼의 상시 부하가 되고, DB가 느려진 날 **전 타깃이 동시에 unhealthy** 판정돼 503 전멸(theory §3)로 번집니다. 헬스체크는 "이 프로세스가 요청을 받을 수 있나"만(가볍고 의존성 없는 경로 — podinfo의 /healthz처럼). 의존성 헬스는 별도 모니터링(12)의 몫.

## 실무 사고 사례

> "배포할 때마다 Sentry에 502가 수십 개 떠요. 몇 초면 사라지니까 무시 중이에요." — 반년을 그렇게 살던 팀이 트래픽이 3배가 된 뒤 마주한 것: 같은 몇 초가 이제 수백 건이고, 재시도 없는 결제 콜백이 그 안에 섞여 있었습니다. 조사 결과 원인은 셋의 합작: readiness gate 미설정(입장), preStop 없음(퇴장), 그리고 배포 밖에서도 나던 간헐 502는 keep-alive 역전이었습니다. 수정은 코드가 아니라 설정 네 줄 — ns 라벨, preStop 20s, deregistration 30s, 앱 keep-alive 75s. 검증은 lab-02 방식 그대로: 부하를 흘리며 배포해 Success 100%를 확인하고, 그 명령을 CI의 배포 후 단계에 박았습니다. 교훈: **"몇 초의 5xx"는 트래픽에 비례해 자라는 부채이고, 갚는 방법은 측정하며 배포하는 습관입니다.**
