# 39 — Rook 심층: Ceph를 K8s에서 운영하는 오퍼레이터

> 05의 스토리지 지도에서 "Rook은 스토리지가 아니다"라는 통과 의례로 만난 그것. Rook은 데이터를 저장하지 않습니다 — **Ceph(분산 스토리지 시스템)를 K8s에서 운영하는 오퍼레이터**입니다. 05에서 배운 "시스템 vs 오케스트레이터" 구분의 대표 사례이고, 08의 오퍼레이터 패턴(운영 지식의 코드화)이 가장 복잡한 도메인(분산 스토리지)에 적용된 예입니다. 이 모듈은 Ceph의 구조(그래야 Rook을 이해합니다), Rook이 Ceph의 무엇을 자동화하나, 그리고 05·09의 스테이트풀 판단이 "스토리지 시스템 자체"에 적용되는 극한을 팝니다.

## 학습 목표

1. Ceph의 아키텍처(OSD·MON·MGR·CRUSH)를 이해합니다 — Rook을 알려면 Ceph를 알아야
2. Rook 오퍼레이터가 Ceph의 무엇을 자동화하나(설치·확장·복구·업그레이드)를 압니다
3. 블록·파일·오브젝트를 한 시스템(Ceph)에서 제공하는 통합 스토리지를 압니다
4. 08의 오퍼레이터 Capability Level이 Rook-Ceph에 적용되는 지점을 압니다
5. "언제 Rook-Ceph인가"(온프레·통합 스토리지) vs 관리형·단순 대안(Longhorn)을 판단합니다

## 선행: 05(스토리지 지도·시스템vs오케스트레이터 — 필수), 08(오퍼레이터), 09(스테이트풀), 21(분산 합의) · 도구: kind, kubectl (개념 중심)
## 비용: 없음 (kind — Ceph는 무거워 개념 중심)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-ceph-and-rook.md](./lab-01-ceph-and-rook.md) — Ceph 구조, Rook 자동화
3. [lab-02-capability-and-judgment.md](./lab-02-capability-and-judgment.md) — Capability Level, 판단
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 1.5h
