# 자가 점검 퀴즈

**Q1.** liveness/readiness/startup 실패의 결과를 각각 한 단어로.

**Q2.** "DB 연결 끊김"을 liveness로 검사하면 안 되는 이유를 사고 시나리오로 설명하세요.

**Q3.** READY 0/1인데 RESTARTS 0인 Pod — 무슨 상황이고 트래픽은 어떻게 되는가요?

**Q4.** 기동에 3분 걸리는 앱의 probe 구성을 설계하세요 (수치 포함).

**Q5.** preStop `sleep 5`가 막아주는 레이스 컨디션을 설명하세요.

**Q6.** `periodSeconds: 10, failureThreshold: 3` liveness의 최악 감지 시간은?

**Q7.** 무중단 배포의 4가지 조각(이 모듈 기준)을 나열하고 각각이 막는 실패를 쓰라.

---

## 정답

**A1.** liveness: **재시작**. readiness: **차단**(명단 제외). startup: **유예**(다른 probe 보류).

**A2.** DB가 1분 끊기면 모든 Pod의 liveness가 동시 실패 → 전체 재시작 → DB 복구 후에도 전 Pod 콜드스타트로 2차 장애. 재시작은 DB를 고치지 못하므로 "재시작이 치료가 되는 상태"라는 liveness의 전제에 어긋납니다. readiness였다면 트래픽만 차단했다가 복구 시 자동 복귀.

**A3.** readiness probe 실패 상태. 컨테이너는 살아 있고(재시작 없음) EndpointSlice에서 빠져 **트래픽을 받지 않습니다.**

**A4.** `startupProbe: { httpGet, periodSeconds: 10, failureThreshold: 24 }` (최대 4분 유예) + 통과 후 적용될 `livenessProbe`(보수적: period 10, threshold 3, timeout 5) + `readinessProbe`(민감해도 됨: period 5). initialDelay로만 때우는 것은 오답에 가깝습니다.

**A5.** Pod 삭제 시 "엔드포인트 제거 전파"(A)와 "SIGTERM"(B)이 **병렬**이라, 앱이 SIGTERM에 즉시 닫으면 아직 규칙이 남은 경로에서 오는 요청이 거부됩니다. sleep 5는 B를 지연시켜 A가 끝난 뒤 종료 절차를 시작하게 합니다.

**A6.** 직전 검사 직후 죽은 경우: 10×3 = **30초** (+timeout). 

**A7.** ① readinessProbe — 준비 안 된 새 Pod로의 트래픽 차단 ② `maxUnavailable: 0` — 배포 중 용량 부족 방지 ③ preStop sleep — 종료 레이스의 connection refused 방지 ④ 앱의 SIGTERM drain — 진행 중 요청 절단 방지.
