# 흔한 함정 5선

## 1. 한 Pod에 앱을 여러 개 넣기 (마이크로 모놀리스)

"web + api + db를 한 Pod에" — 같이 스케일되고 같이 죽는 운명 공동체가 됩니다. 기준: **"이 둘은 반드시 1:1로 같이 떠야 하는가요?"** 아니라면 Pod를 나누고 Service로 연결. 멀티 컨테이너는 사이드카류 보조 기능에만.

## 2. 같은 Pod 안 포트 충돌

NET namespace를 공유하므로 두 컨테이너가 같은 포트를 들으면 한쪽이 `address already in use`로 죽습니다. Pod 내 포트는 컨테이너끼리 나눠 써야 합니다.

## 3. SIGTERM 무시하는 앱

PID 1로 도는 셸 스크립트(`sh -c "..."`)는 기본적으로 시그널을 자식에게 전달하지 않습니다 → 매 배포마다 grace period를 꽉 채우고 SIGKILL → 요청 유실. 해결: `exec` 로 앱을 PID 1로 만들거나, 앱에서 SIGTERM 핸들러 구현 (모듈 14).

## 4. init 컨테이너에 안 끝나는 명령

lab-02 Step 2에서 본 그대로 — init은 "종료"가 계약입니다. 계속 살아야 하는 보조 프로세스는 `restartPolicy: Always`를 붙여 sidecar로. 반대로, 옛 자료처럼 sidecar를 일반 컨테이너로 넣으면 시작 순서 보장이 없습니다.

## 5. `kind: Pod`를 운영에 사용

직접 만든 Pod(naked Pod)는 노드 장애 시 부활하지 않고, 이미지 업데이트도 불가. 운영은 항상 Deployment/StatefulSet/Job 등 컨트롤러를 통합니다. naked Pod가 허용되는 곳: 학습, 일회성 디버깅(`kubectl run` 임시 사용) 정도.

## 실무 사고 사례

> 메시 도입 전 한 팀이 envoy 프록시를 **일반 컨테이너** 사이드카로 추가했습니다. 배포 직후 간헐적 502 — 앱은 떴는데 프록시가 아직 안 떠서 트래픽이 블랙홀로. 네이티브 sidecar(`initContainers` + `restartPolicy: Always`)로 바꾸자 "프록시가 앱보다 먼저 뜨고 나중에 죽는" 순서가 보장되며 해결. — 시작/종료 **순서**는 우연이 아니라 선언해야 합니다.
