# 이론 — Probe 3종, 종료 시퀀스, 무중단의 조건

> **🌱 17세 눈높이 비유: 식당 직원 관리**
> - **liveness** = "쓰러졌나요?" 확인. 쓰러졌으면 **교대 인력 투입(재시작)**. 단, 멀쩡히 일하는 직원을 "응답이 0.5초 늦었다"고 교체하기 시작하면 주방 전체가 마비됩니다.
> - **readiness** = "주문 받을 수 있나요?" 확인. 손 씻는 중이면 **주문만 안 넘깁니다** — 자르지 않습니다!
> - **startup** = 신입 교육 기간. 교육 끝날 때까지는 위 두 검사를 **유예**해줍니다.
> - **graceful shutdown** = 퇴근 절차: "신규 주문 그만 받고(명단 제거) → 만들던 요리 마저 내고(드레인) → 퇴근(종료)". 갑자기 앞치마 벗고 나가면(즉시 종료) 만들던 요리가 버려집니다(5xx).

---

## 1. Probe 메커니즘

검사 주체는 **kubelet**(그 노드의)입니다. 방식 4종:

```yaml
livenessProbe:
  httpGet: { path: /healthz, port: 8080 }   # 200~399면 성공 (가장 흔함)
  # tcpSocket: { port: 5432 }               # 연결되면 성공
  # exec: { command: [pg_isready] }         # exit 0이면 성공
  # grpc: { port: 9090 }                    # gRPC Health 프로토콜
  initialDelaySeconds: 10   # 첫 검사 유예
  periodSeconds: 10         # 검사 주기
  timeoutSeconds: 1         # 응답 대기 (기본 1초 — 의외로 짧습니다!)
  failureThreshold: 3       # 연속 N번 실패 시 "실패" 판정
  successThreshold: 1       # (readiness만 조정 의미 있음)
```

감지 지연 계산: 최악 `periodSeconds × failureThreshold` (위 설정 = 최대 30초 후 재시작).

## 2. 3종의 정확한 의미

### liveness — "재시작하면 풀리는 상태인가"
- 실패 → kubelet이 컨테이너 **재시작** (Pod는 유지, IP 유지 — 모듈 03)
- 적합: 데드락, 무한 루프, 응답 불능 — **재시작이 치료가 되는 것만**
- 부적합: 외부 의존성(DB/캐시) 장애 — 재시작해도 안 풀리고, 전 Pod 동시 재시작 폭풍만 유발

### readiness — "트래픽 받을 수 있는가"
- 실패 → **EndpointSlice에서 제외** (모듈 05의 그 명단). 컨테이너는 건드리지 않음
- 회복하면 자동 복귀. "일시적 과부하/워밍업/의존성 끊김"에 알맞습니다
- 롤링 업데이트의 "Ready 기준"(모듈 04)이 바로 이것

### startup — "기동 완료까지 봐주기"
- 성공할 때까지 liveness/readiness를 **보류**. 성공하면 임무 종료(이후 관여 안 함)
- 용도: 시작이 느린 앱(JVM, 마이그레이션). `failureThreshold: 30, periodSeconds: 10` = 최대 5분 유예
- startup 없이 liveness의 initialDelay만으로 버티면: 빠른 기동 때는 시간 낭비, 느린 기동 때는 못 뜨고 재시작 무한루프

## 3. 종료 시퀀스 정밀 분해 (모듈 03 확장)

```
삭제 명령
  ├─(병렬 A) EndpointSlice 제거 → kube-proxy 규칙 갱신 → LB 타겟 제거   ← 시간 걸림!
  └─(병렬 B) preStop hook → SIGTERM → grace period → SIGKILL
```

**A와 B가 병렬**이라는 것이 모든 문제의 근원: B(SIGTERM)가 A(전파)보다 먼저 도달합니다. 앱이 SIGTERM에 즉시 소켓을 닫으면, 아직 규칙이 남은 노드/LB에서 오는 요청이 connection refused.

### 표준 해법

```yaml
lifecycle:
  preStop:
    exec: { command: [sh, -c, "sleep 5"] }   # A의 전파를 기다림 (NLB/ALB면 더 길게)
terminationGracePeriodSeconds: 30             # preStop 시간 포함!
```

+ 앱 코드: SIGTERM 수신 → 신규 수락 중단 → 진행 중 요청 완료 → 종료 (Go의 `http.Server.Shutdown`, Spring `graceful`, Node `server.close` 등).

> **💡 grace period에 preStop 실행 시간이 포함**됩니다. preStop sleep 25 + 앱 drain 20초 필요라면 grace 30초는 부족 — SIGKILL로 잘립니다.

## 4. 케이스 스터디 — 무엇이 무중단을 깨는가

| 증상 | 빠진 조각 |
|------|----------|
| 배포 직후 수 초 5xx | readiness 없음/부실 → 준비 안 된 새 Pod에 트래픽 |
| 배포 마지막에 짧은 connection refused | preStop sleep 없음 → 종료 레이스 |
| 배포 때마다 일부 요청 30초 후 504 | 앱이 SIGTERM 무시 → SIGKILL에 끊김 |
| 평시에 간헐 재시작 (RESTARTS 증가) | liveness가 과민(timeout 1s) 또는 외부 의존성 검사 |
| 트래픽 급증 시 전체 마비 | liveness가 과부하 때 실패 → 재시작 → 남은 Pod 더 과부하 (폭풍) |

## 5. 소스코드에서 확인하기

- probe 실행 워커: `pkg/kubelet/prober/worker.go` — 컨테이너마다 probe 종류별 고루틴이 도는 구조
- readiness 결과가 명단으로: `pkg/controller/endpointslice/` 가 Pod의 Ready condition을 보고 슬라이스 갱신

## 요약 카드

| 질문 | 답 |
|------|----|
| liveness 실패의 결과? | 컨테이너 재시작 (kubelet) |
| readiness 실패의 결과? | EndpointSlice 제외 — 트래픽만 차단 |
| startup의 역할? | 성공까지 다른 probe 보류 (기동 유예) |
| liveness에 DB 체크? | 금지 — 재시작 폭풍 (readiness 소관) |
| preStop sleep의 이유? | 명단 제거 전파와 SIGTERM의 레이스 해소 |
| grace period의 범위? | preStop + 종료 처리 전체 포함 |
