# 흔한 함정 5선

## 1. liveness에 외부 의존성 검사

`/healthz`가 DB ping까지 하는데 그걸 liveness에 연결 → DB 1분 장애 = **전체 Pod 동시 재시작** = DB 복구 후에도 콜드스타트 폭풍으로 2차 장애. liveness는 "프로세스 자체의 회생 불능"만, 의존성은 readiness로.

## 2. timeoutSeconds 기본값 1초 방치

GC 멈춤, 순간 부하로 1초를 넘기는 건 흔합니다 → 멀쩡한 Pod가 unhealthy 판정. liveness는 timeout 5s 안팎 + failureThreshold 3 이상으로 관용 있게. (반대로 readiness는 민감해도 부작용이 "잠깐 명단 제외"라 상대적으로 안전)

## 3. readiness와 liveness에 같은 엔드포인트

엔드포인트가 의존성을 검사하면 함정 1로, 안 하면 readiness가 무의미해집니다. 관례: `/livez`(프로세스 생존만) / `/readyz`(의존성 포함) 분리 — API 서버 자신도 이 두 경로를 씁니다.

## 4. SIGTERM을 PID 1 셸이 삼키는 문제

`command: ["sh", "-c", "java -jar app.jar"]` — SIGTERM이 sh에서 멈추고 java에 전달 안 됨 → 매번 30초 후 SIGKILL. 해결: `exec java -jar app.jar` 또는 ENTRYPOINT exec 형식 `["java","-jar","app.jar"]`. (모듈 03 pitfall의 재림 — 그만큼 흔합니다)

## 5. preStop sleep과 grace period의 산수 실수

preStop sleep 20 + 앱 drain 최대 15초인데 grace 30초 → drain 도중 SIGKILL. **grace ≥ preStop + drain 최대 시간 + 여유.** 특히 ALB는 deregistration delay(기본 300초!)가 있어 EKS에서는 LB 설정과 함께 계산해야 합니다 (eks 파트 14).

## 실무 사고 사례

> 트래픽 피크에 응답이 1.2초로 늘자 liveness(timeout 1s)가 연쇄 실패 → Pod 재시작 → 남은 Pod에 부하 집중 → 더 느려짐 → 더 많은 재시작. 10분 만에 전 서비스 다운. 원인 코드는 한 줄도 안 바뀌었습니다 — **probe 설정이 장애를 만들었습니다.** 사후 조치: liveness timeout 5s/threshold 5로 완화, 의존성 검사 분리, "probe 변경은 코드 리뷰 대상" 정책화. 교훈: **probe는 안전장치이자 흉기입니다. 보수적으로 시작하세요.**
