# 흔한 함정 5선

## 1. "StatefulSet = DB 운영 완성"이라는 착각

StatefulSet은 신원/디스크/순서만 보장합니다. 복제 설정, 백업, 장애 승격, 스키마 관리는 전부 별도 — 그게 없으면 "디스크 달린 Pod 3개"일 뿐입니다. 실무 DB는 Operator(CloudNativePG, Strimzi 등)나 관리형(RDS)을 먼저 검토하세요.

## 2. PVC 잔존을 모르고 비용 폭탄 / 또는 알고도 지워서 데이터 증발

양방향 함정: ① 스케일인/삭제 후 PVC가 남아 EBS 비용이 계속 나갑니다(모름) ② "정리하자"며 data-db-0 PVC를 지웠는데 그게 운영 데이터였습니다(앎의 오용). `persistentVolumeClaimRetentionPolicy`를 의도에 맞게 명시하고, 운영 데이터 PVC에는 보호 라벨+백업을.

## 3. Headless Service 빼먹기 (serviceName 불일치)

serviceName이 가리키는 Headless Service가 없으면 Pod는 떠도 **멤버 DNS가 안 생깁니다** — "db-0.db가 안 풀려요". StatefulSet과 Headless Service는 한 몸으로 배포하세요 (manifests처럼 같은 파일에).

## 4. 0번이 막히면 전부 막힙니다

순차 기동에서 db-0이 못 뜨면(스토리지 장애, 이미지 오류) db-1, db-2는 시작조차 안 합니다 — 단일 멤버 장애가 전체 기동 블로킹으로. 순서가 필요 없는 워크로드(독립 캐시 등)는 `podManagementPolicy: Parallel`로 풀어줘라.

## 5. 클라이언트가 일반 Service처럼 접속

Headless `db`로 connect하면 DNS가 멤버 IP들을 주지만 **분배/failover를 해주지 않습니다.** 읽기/쓰기 분리(쓰기는 db-0, 읽기는 아무나)는 앱 또는 프록시 레이어의 책임. "가끔 쓰기가 replica로 가요"는 거의 항상 클라이언트 접속 문자열 문제입니다.

## 실무 사고 사례

> Kafka(StatefulSet)의 broker-2가 노드 장애로 Terminating에 고착. 대기가 답답한 엔지니어가 `--force` 삭제 → 새 broker-2가 다른 노드에 떴는데, **옛 노드는 사실 네트워크 단절이었을 뿐 broker-2 프로세스가 살아 있었습니다.** 네트워크 복구 순간 같은 ID 두 개가 클러스터에 — 파티션 일부 데이터 비일관으로 며칠간 정합성 복구 작업. 교훈: force delete 전 **노드의 물리적 사망을 확정**(인스턴스 종료 확인 → `kubectl delete node`)하는 runbook을 따르라. "기다림"이 가장 싼 복구일 때가 있습니다.
