# 36 — Vitess 심층: MySQL을 무한히 늘리는 법

> 09의 데이터 지도에서 분산 DB 갈래, "MySQL을 무한히"라 소개한 그것. YouTube가 단일 MySQL의 한계에 부딪혀 만든 프로젝트로, **샤딩(수평 분할)을 애플리케이션에서 데이터베이스 계층으로 옮깁니다.** 앱은 하나의 큰 MySQL로 보이지만 뒤에서는 수백 개의 샤드로 나뉘어 있습니다 — 그 마법의 구조(VTGate가 쿼리를 라우팅, VTTablet이 각 샤드 관리)와, 09에서 배운 "스테이트풀을 K8s에" 판단이 가장 극단적으로 적용되는 이유를 팝니다. 상태의 무게와 샤딩의 복잡성을 정직하게 다룹니다.

## 학습 목표

1. 샤딩의 문제(단일 DB의 한계)와 Vitess가 그것을 DB 계층으로 옮긴 방식을 압니다
2. Vitess 아키텍처(VTGate·VTTablet·VSchema·Topology)와 쿼리 라우팅을 이해합니다
3. 샤딩 키(sharding key)와 VIndex, 리샤딩(resharding)의 무중단 원리를 압니다
4. 09의 스테이트풀 판단이 Vitess에서 극대화되는 지점(운영 복잡도·상태)을 압니다
5. "언제 Vitess인가"(단일 DB의 벽) vs 대안(관리형·다른 분산 DB) 판단을 압니다

## 선행: 09(데이터 지도·스테이트풀 판단 — 필수), 05(스토리지), 21(etcd 유사) · 도구: kind, kubectl (개념 중심)
## 비용: 없음 (kind — Vitess는 무거워 개념 중심)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-sharding-and-routing.md](./lab-01-sharding-and-routing.md) — 샤딩 구조, 쿼리 라우팅
3. [lab-02-resharding-and-judgment.md](./lab-02-resharding-and-judgment.md) — 리샤딩, 판단
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 1.5h
