# 24 — 대규모 관측: 클러스터 하나를 넘어설 때

> production 트랙의 마무리. 지금까지의 스택은 클러스터 하나의 세계였습니다 — 조직이 크면 질문이 바뀝니다: 클러스터 30개의 메트릭을 **한 화면에서** 보려면? 팀 100개가 한 저장소를 쓰면 **서로를 침범하지 않게**(테넌시) 하려면? Prometheus의 벽(08)을 자체로 넘는 Thanos/Mimir(cncf 45의 그것 — 오브젝트 스토리지·글로벌 쿼리)는 언제 AMP(14) 대신 정당한가? 이 모듈은 대규모 관측의 세 축 — **집약 토폴로지**(중앙 vs 연합), **테넌시**(격리·쿼터·귀속), **글로벌 쿼리와 고가용성**(이중 수집·중복 제거) — 을 다루고, Thanos를 실습으로 맛본 뒤, 규모별 아키텍처 판단(단일→멀티→초대규모)의 최종 지도를 그립니다.

## 학습 목표

1. 멀티클러스터 관측의 토폴로지(중앙 집약 vs 연합 vs 하이브리드)를 비교합니다
2. Thanos의 구조(sidecar·store·query·compactor)와 오브젝트 스토리지 장기 저장을 이해합니다
3. HA 수집(이중 Prometheus)과 중복 제거의 원리를 압니다
4. 테넌시 설계(라벨 격리·쿼터·귀속 — 22의 조직 장치의 기술판)를 압니다
5. 규모별 판단 지도(단일 스택→AMP 집약→Thanos/Mimir)를 완성합니다

## 선행: 08(Prometheus의 벽), 14(AMP — 비교축), 22(귀속), cncf 45(Thanos 자리매김) · 도구: kind, kubectl, helm
## 비용: 없음 (kind + MinIO로 오브젝트 스토리지 흉내)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-thanos-global-view.md](./lab-01-thanos-global-view.md) — 두 "클러스터"의 메트릭을 Thanos로 한 화면에
3. [lab-02-scale-judgment.md](./lab-02-scale-judgment.md) — HA·테넌시·규모별 판단 지도
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2.5h
