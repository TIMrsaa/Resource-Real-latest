# 37 — TiKV 심층: 자동 샤딩 분산 KV의 내부

> 09의 데이터 지도에서 분산 DB 갈래, 36(Vitess)의 반대편. Vitess가 기존 MySQL을 샤딩으로 확장한다면(명시적 샤딩 + MySQL 계보), TiKV는 처음부터 분산으로 설계된 트랜잭션 키-값 저장소입니다 — **자동 샤딩(Region)과 Raft 복제**로 사용자가 샤딩을 신경 쓰지 않습니다. TiDB(MySQL 호환 SQL 계층)의 스토리지 층이자 독립 KV로도 쓰입니다. 이 모듈은 21에서 배운 Raft가 여기서 어떻게 데이터 저장에 쓰이는지(etcd의 Raft와 같은 계보), Region 자동 분할·이동의 원리, 그리고 Vitess와의 근본적 설계 차이를 팝니다.

## 학습 목표

1. TiKV의 아키텍처(TiKV 노드·PD·Region)와 자동 샤딩(Region 분할)을 이해합니다
2. Raft가 데이터 복제에 쓰이는 방식(21의 etcd Raft와 같은 계보, 다른 스케일)을 압니다
3. PD(Placement Driver)의 역할(Region 스케줄링·밸런싱)과 MVCC 트랜잭션을 압니다
4. Vitess(명시적 샤딩·MySQL) vs TiKV(자동 샤딩·자체 분산)의 설계 대비를 완성합니다
5. TiKV/TiDB의 자리와 09의 스테이트풀 판단을 압니다

## 선행: 09(데이터 지도), 21(etcd·Raft — 필수), 36(Vitess 대비) · 도구: kind, kubectl (개념 중심)
## 비용: 없음 (kind — 개념 중심)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-regions-and-raft.md](./lab-01-regions-and-raft.md) — Region 자동 샤딩, Raft 복제
3. [lab-02-vitess-comparison.md](./lab-02-vitess-comparison.md) — Vitess와 설계 대비, 판단
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 1.5h
