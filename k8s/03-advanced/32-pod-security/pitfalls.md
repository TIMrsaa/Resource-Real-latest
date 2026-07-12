# 흔한 함정 5선

## 1. "PSA 라벨 붙였으니 끝" — 소급 적용 없음

enforce는 **새 Pod 생성 시점**에만 검사합니다 — 라벨 부착 전부터 돌던 위반 Pod는 그대로 삽니다. 강화 작업 = 라벨 + **기존 워크로드 전수 점검/재배포**까지. `kubectl get pods -n X -o yaml | grep privileged` 같은 감사를 병행하세요.

## 2. restricted를 빅뱅 enforce

준비 안 된 ns에 바로 enforce=restricted → 다음 배포/노드 장애 재생성부터 전부 거부 — 새벽에 "Pod가 하나도 안 떠요". 정석: **warn+audit로 위반 목록 수집 → 워크로드 수정 → enforce 승격** (lab-02의 순서). 모듈 23 점진 도입 원칙의 재림.

## 3. 이미지의 root 의존을 securityContext로만 풀려는 시도

runAsUser: 10001을 강제했더니 앱이 "permission denied"(자기 파일이 root 소유) — 이미지가 root 전제로 만들어진 탓. 근본 해법은 **이미지 수정**(USER 지시, 파일 소유권 — 모듈 01). fsGroup/initContainer chown은 임시방편. 레거시 불가 시 user namespaces가 절충.

## 4. 모니터링/에이전트 예외를 일반 ns에 풀어주기

"APM 에이전트가 hostPath가 필요하대요" → 일반 ns의 PSA를 privileged로 — 그 ns 전체의 둑이 무너집니다. 특권 필요 컴포넌트는 **전용 ns에 격리**하고 거기만 등급을 낮춰라 (kube-system이 그 모델). 예외는 ns 단위로만.

## 5. seccomp을 끄는 "성능 미신"

"오버헤드 있을까 봐" RuntimeDefault를 뺍니다 — 실제 오버헤드는 거의 측정 불가 수준이고, 끄는 순간 커널 공격면(수백 시스템콜)이 전부 열립니다. 끄는 결정에는 측정 근거가 있어야 합니다 (대부분 없습니다).

## 실무 사고 사례

> 이미지 처리 서비스의 라이브러리 취약점(RCE)으로 컨테이너가 장악됐습니다. 그러나: ① non-root + drop ALL이라 권한 상승 실패 ② readOnlyRootFilesystem이라 크립토마이너 설치 실패 ③ seccomp이 커널 익스플로잇 시도(mount 콜)를 차단 ④ NetworkPolicy(모듈 15)가 횡적 이동 차단 ⑤ automountServiceAccountToken: false라 훔칠 토큰도 없음. 공격자는 그 컨테이너의 메모리 안에서 끝났고, 침입 흔적은 Falco(cncf 파트)가 잡아냈습니다. — 이 모듈의 설정들이 "유난"이 아니라 **다층 방어(defense in depth)의 실전 가치**임을 보여주는 교과서 사례. 어느 한 층도 단독으론 완벽하지 않지만, 겹치면 공격 비용이 기하급수로 오릅니다.
