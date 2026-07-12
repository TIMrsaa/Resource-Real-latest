# 흔한 함정 5선

## 1. "ns가 다르니 안전하겠지" (네트워크)

lab-01 Step 2에서 봤듯 ns 간 통신은 기본 **전부 허용**입니다. dev에서 prod DB 접속, 침해당한 Pod의 수평 이동 — 전부 가능. 운영 클러스터는 NetworkPolicy 기본 거부(모듈 15)가 출발선.

## 2. `kubectl delete namespace`의 파괴력

ns 삭제 = 안의 모든 리소스(PVC 포함!) 연쇄 삭제. 모듈 08 사고 사례의 그 버튼입니다. 삭제 전 `kubectl get all,pvc,secret -n X` 확인 습관. 또한 finalizer 때문에 Terminating에 영원히 걸리는 경우가 있는데, 원인(남은 리소스/응답 없는 웹훅)을 찾아야지 finalizer 강제 제거는 최후 수단입니다 (모듈 24에서 원리).

## 3. 환경 분리를 ns로만 — prod와 dev를 한 클러스터에

ns는 소프트 격리입니다: 커널/노드/control plane을 공유하고, 시끄러운 이웃(noisy neighbor)과 클러스터 장애 폭발 반경을 같이 집니다. 일반 권고: **prod는 클러스터 분리**, dev/staging은 ns 분리 + Quota. (중간 지대는 모듈 34 멀티테넌시)

## 4. 라벨 값에 들어갈 수 없는 것

63자 초과, 공백, 한글, `/`(키 prefix 제외) — 라벨 값은 엄격합니다. "버전 설명을 라벨에" 넣다가 거부되면, 그건 annotation감입니다. 또 라벨 값은 항상 **문자열**: `version: 1.2`는 YAML이 숫자로 파싱해 에러 — `"1.2"`로 인용.

## 5. Quota만 걸고 LimitRange를 빼먹기

requests 명시가 없는 Pod는 Quota ns에서 전부 거부됩니다 — "갑자기 아무 Pod도 안 만들어져요". Quota와 LimitRange(기본값 주입)는 세트로 배포하세요. 반대 함정: LimitRange의 기본 limits가 너무 작으면 전 Pod가 OOMKilled 행진.

## 실무 사고 사례

> 비용 절감 차원에서 안 쓰는 ns를 정리하던 중, `kubectl delete ns analytics`를 실행. 그 안에 있던 PVC(Retain 아님)와 함께 1년치 분석 데이터 삭제. 진짜 문제는 **이름**이었습니다 — 팀은 "analytics-old"를 지우려 했는데 탭 자동완성이 "analytics"를 먼저 잡았습니다. 교훈: 파괴적 명령은 `--dry-run=client`로 먼저, 그리고 운영 데이터 ns에는 라벨(`protected=true`)을 붙여 삭제 스크립트에서 제외 처리.
