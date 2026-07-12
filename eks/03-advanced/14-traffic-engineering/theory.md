# 이론 — ALB의 손잡이들: 타임아웃 정합, 알고리즘, 입장과 퇴장

> **🌱 17세 눈높이 비유: 대형마트의 계산대 매니저**
> ALB는 계산대(Pod)들 앞에 선 매니저입니다:
> - **idle timeout** = "손님이 아무 것도 안 하고 N초 서 있으면 자리를 비워주세요" — 계산이 오래 걸리는 손님(긴 요청)도 이 규칙에 잘립니다(504)
> - **알고리즘** = 손님 배정법: 순서대로 돌리기(round robin) vs **줄이 제일 짧은 계산대로**(least outstanding)
> - **slow start** = 신입 계산원에겐 손님을 서서히 늘려줍니다
> - **draining(deregistration)** = 교대하는 계산원은 새 손님을 안 받고 잡은 손님만 마무리
> - **readiness gate** = 계산대 "OPEN" 등이 켜진 걸 매니저가 확인한 뒤에야 손님을 보냅니다
> - 5xx = 계산원이 갑자기 자리를 뜸(502) / 열린 계산대가 0개(503) / 계산이 하염없음(504)

---

## 1. 경로 해부 — 손잡이가 사는 곳

```
client ──TLS/HTTP──▶ ALB listener ──rule──▶ Target Group ──▶ target
        │                │                    │                └ target-type ip = Pod ENI 직행 (08)
        │                │                    ├ 알고리즘 / slow_start / deregistration_delay
        │                │                    └ health check (경로·주기·임계)
        │                └ idle_timeout (LB 속성 — TG 아님!)
        └ 클라이언트 자신의 timeout
```

같은 "타임아웃"이라도 사는 곳이 다릅니다 — LB 속성은 `load-balancer-attributes`, TG 속성은 `target-group-attributes` annotation(컨트롤러가 반영, 08의 그 구조).

## 2. 타임아웃 3종 정렬 — 502를 예방하는 부등식

```
앱의 keep-alive timeout  >  ALB idle_timeout(기본 60s)  ≥  클라이언트 기대
```

**왜 앱이 더 길어야 하나**: ALB는 백엔드 커넥션을 keep-alive로 재사용합니다. 앱이 먼저(예: 30s) 닫으면 — ALB가 "아직 살아 있다"고 믿는 커넥션에 요청을 실어 보내는 순간이 생깁니다 → 백엔드가 끊었으니 **502**. 간헐적·재현 불가처럼 보이는 502의 단골 원인이며, 수정은 코드 한 줄(keep-alive를 65s+로)입니다.

**idle의 정확한 뜻**: "커넥션에 바이트가 흐르지 않는 시간". 응답이 idle_timeout 안에 시작되지 않으면 ALB가 대신 **504**를 답합니다 — 긴 작업/롱폴링은 idle_timeout을 그 위로 올리거나 비동기 패턴으로.

## 3. 5xx 분류표 — ALB가 말하는 것과 앱이 말한 것

| 코드 | 낸 쪽 | 전형적 원인 | 첫 확인 |
|------|------|------------|---------|
| 502 | ALB | keep-alive 역전(§2), **죽은/막 종료된 Pod로 전송**(§5), 응답 형식 오류 | 배포 시각과 겹치나요? |
| 503 | ALB | healthy target **0개** — 전멸, 혹은 아직 등록 전 | TG의 healthy count |
| 504 | ALB | idle_timeout 내 무응답 (긴 요청, 백엔드 행) | 요청 소요시간 분포 |
| 5xx | 앱 | 앱 자신의 오류 | 앱 로그 (12의 파이프라인) |

진단의 첫 갈림길: **ALB access log의 `elb_status_code` vs `target_status_code`** — 둘이 다르면 ALB가 만든 오류(위 3형제), 같으면 앱이 만든 오류입니다.

## 4. 배분 알고리즘 — 꼬리는 배정에서 만들어집니다

| | round_robin (기본) | least_outstanding_requests (LOR) |
|---|---|---|
| 규칙 | 순서대로 균등 | **in-flight가 가장 적은** 타깃으로 |
| 타깃이 균질하면 | 충분 | 차이 없음 |
| 느린 타깃이 섞이면 | 느린 곳에도 같은 몫 → 그 몫 전부가 꼬리 | 느린 타깃엔 자연히 덜 감 → 꼬리 절단 |

LOR의 원리는 13의 언어로 자명합니다: outstanding = λ×W (Little's Law) — **W(지연)가 큰 타깃은 outstanding이 쌓여** 배정에서 밀립니다. 지연이 스스로 신호가 되는 것.

- 현실에서 느린 타깃은 늘 생깁니다: GC 중인 JVM, 캐시가 식은 새 Pod, 시끄러운 이웃의 노드
- **주의**: slow_start는 LOR과 **동시 사용 불가** — 새 Pod 보호가 필요하면 둘 중 하나를 고르는 결정입니다 (LOR은 outstanding 기준이라 새 Pod 과부하를 어느 정도 자연 완화합니다)

## 5. 타깃의 입장과 퇴장 — 배포 중 5xx의 해부

### 입장 (새 Pod)

```
Pod 생성 → (k8s) readinessProbe 통과 → Ready
        → (ALB) TG 등록 → health check 통과 → healthy → 트래픽
```

문제: 두 줄은 **독립적으로 진행**됩니다. k8s가 Ready로 보고 옛 Pod를 죽이기 시작했는데 ALB 등록이 아직이라면 → healthy 타깃이 모자라거나 0(503). 해결이 **readiness gate**: ns에 라벨 `elbv2.k8s.aws/pod-readiness-gate-inject: enabled`를 달면 컨트롤러가 Pod 생성 시 readinessGates를 주입 — **"TG에서 healthy"가 Ready의 조건**이 되어 두 줄이 하나로 묶입니다. 롤링 업데이트가 ALB의 속도로 진행됩니다.

### 퇴장 (옛 Pod)

```
삭제 시작 → preStop(sleep N) → SIGTERM → 앱 graceful shutdown → 종료
   ⇅ 병렬로: 엔드포인트 제거 전파 + ALB deregister → draining(새 요청 중단, 기존만 마무리)
```

문제: 전파는 몇 초 걸리는데 Pod가 즉사하면 — ALB가 그 몇 초간 **죽은 주소로** 보냅니다(502). 해결 세트:

1. **preStop sleep 15~30s** — "빠지는 중" 전파가 끝날 때까지 살아서 받습니다
2. `terminationGracePeriodSeconds` > preStop + 앱 shutdown 시간
3. **deregistration_delay** — 기본 300s는 배포를 하염없이 늘립니다: 최장 요청 시간 기준으로(예: 30s) 조정

### 무중단 배포 4종 세트 (lab-02에서 증명)

readiness gate(입장 동기화) + preStop sleep(퇴장 유예) + deregistration_delay 조정(드레이닝) + maxSurge/maxUnavailable(교체 보폭) — 넷 중 하나만 빠져도 "배포 때마다 잠깐 5xx"가 남습니다.

## 6. NLB와 존 이야기

| | ALB (L7) | NLB (L4) |
|---|---|---|
| 보는 것 | HTTP (경로/헤더/메서드) | TCP/UDP flow |
| client IP | X-Forwarded-For 헤더로 | **패킷 그대로 보존** 가능 |
| 타임아웃 | idle 60s (조정) | flow idle 350s (고정) |
| cross-zone | **기본 on** (AZ 간 요금 없음) | **기본 off** — 켜기 전 AZ 간 전송 과금 여부를 요금표로 확인 |
| 자리 | 웹/API | 게임/DB 프록시/고정 IP 요구/극저지연 |

cross-zone off의 NLB + AZ별 Pod 수 불균형 = **AZ별 부하 불균형** (한 존의 Pod들만 뜨겁습니다). 켜거나, Pod를 topologySpreadConstraints로 존에 고르게 펴거나 — LB 계층과 스케줄링 계층이 맞물리는 지점입니다.

## 7. LCU — 트래픽 설계의 가격표

ALB는 시간당 요금 + **LCU**(4축 중 최대값 과금): 신규 커넥션/s, 활성 커넥션, 처리 바이트, 룰 평가. 함의 두 가지: ① keep-alive 재사용은 "신규 커넥션" 축을 깎는 돈 문제이기도 하다 ② 룰 수십 개짜리 Ingress는 룰 평가 축으로 과금될 수 있습니다. 청구서의 LCU 축이 무엇이었는지 보는 것이 튜닝의 시작.

## 8. 소스/도구에서 확인하기

- ALB Controller annotation 사전: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/
- readiness gate 문서: 같은 사이트 `deploy/pod_readiness_gate/`
- ALB 5xx 트러블슈팅(공식): https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-troubleshooting.html
- access log 필드 명세 (elb vs target status code)

## 요약 카드

| 질문 | 답 |
|------|----|
| 타임아웃 부등식? | 앱 keep-alive > ALB idle(60s) — 역전 시 간헐 502 |
| 502/503/504 구분? | 백엔드 절단 / healthy 0 / idle 내 무응답 — elb vs target status code로 |
| LOR이 꼬리를 줄이는 원리? | outstanding=λW — 느린 타깃은 스스로 배정에서 밀림 |
| LOR과 slow start? | 동시 사용 불가 — 택일 |
| 입장 동기화? | readiness gate — "TG healthy"를 Pod Ready 조건으로 |
| 퇴장 유예? | preStop sleep + deregistration_delay(기본 300s 조정) |
| NLB cross-zone 기본? | off — AZ 불균형 주의 (ALB는 on) |
