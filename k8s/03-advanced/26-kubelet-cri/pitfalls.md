# 흔한 함정 5선

## 1. 전 워크로드 BestEffort 운영

requests를 "귀찮아서" 전부 생략 — 평시엔 굴러가지만 노드 압박의 첫 희생자 명단에 전원 등록한 셈입니다. 게다가 스케줄러는 빈 requests를 0으로 계산해 노드를 과적합니다 — 압박을 스스로 만드는 구조. **requests는 보험료입니다** (LimitRange 기본값 — 모듈 09 — 가 최소 안전망).

## 2. Evicted Pod 시체를 방치

Evicted Pod는 Failed 상태로 **남습니다** (자동 정리 한도가 있지만 느슨). 수백 개 쌓이면 kubectl 출력/etcd만 어지럽힙니다. 정리: `kubectl delete pods --field-selector status.phase=Failed -A`. 근본 대응은 eviction이 왜 났는지(노드 과적, 디스크) 추적.

## 3. crictl로 컨테이너를 "만드는" 디버깅

crictl run으로 노드에 임시 컨테이너를 만들면 — kubelet은 그 존재를 모르고, 자원 계산에서도 빠지며, 정리도 안 됩니다 (유령). crictl은 **조회/진단(pods, ps, logs, inspect)** 용으로, 생성은 kubectl debug로.

## 4. 노드 디스크를 이미지가 다 먹는 문제

대형 이미지를 자주 바꾸는 클러스터에서 nodefs 압박 → 이미지 GC가 따라가지 못하면 DiskPressure → eviction 연쇄. 신호: `crictl images` 수백 줄, describe node의 ephemeral-storage 압박. 대응: 이미지 경량화(모듈 01), GC 임계 튜닝, 노드 디스크 증설. "디스크 풀"은 노드 장애 원인 상위권입니다.

## 5. kubelet 로그를 안 보고 노드 문제를 추측

NotReady/ContainerCreating 고착의 답은 거의 항상 `journalctl -u kubelet`에 문자 그대로 적혀 있습니다 (CNI 에러, 볼륨 마운트 타임아웃, 런타임 무응답...). API 서버 쪽 이벤트는 요약본일 뿐 — **노드 문제는 노드에서 읽어라.**

## 실무 사고 사례

> 야간 배치가 로그를 컨테이너 내부 파일(쓰기 레이어)에 폭풍 기록 — emptyDir도 PVC도 아니라서 모니터링 사각지대였습니다. 노드 디스크 85% → kubelet 이미지 GC 발동(무관한 이미지 삭제로 아침 배포가 전부 재pull) → 90% → DiskPressure → **그 노드의 서비스 Pod들 연쇄 eviction.** 배치 하나가 노드 전체를 무너뜨렸습니다. 대응: ① 컨테이너 로그는 stdout으로(수집기가 관리) ② ephemeral-storage requests/limits 설정(이걸 넘으면 그 Pod만 eviction) ③ nodefs 사용률 알람. 교훈: **디스크는 메모리보다 조용히, 더 넓게 무너뜨립니다.**
