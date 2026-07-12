# 09 — 지도: 데이터·스트리밍·데이터베이스 — 상태를 다루는 시스템들

> K8s에서 가장 늦게 정복된 영역이자, 오퍼레이터 패턴(08)이 가장 절실했던 영토입니다. 이 지도는 세 부류로 갈립니다: **K8s 자신의 심장인 etcd**(모든 상태의 원천), **메시징·스트리밍**(NATS·Pulsar·Strimzi/Kafka·CloudEvents), **분산 데이터베이스**(TiKV·Vitess). 그리고 이 카테고리의 진짜 질문은 프로젝트 선택이 아닙니다 — "**스테이트풀 워크로드를 K8s에 올릴 것인가**"이고, 그 답을 오퍼레이터 성숙도(08)와 스토리지 지도(05)가 함께 결정합니다.

## 학습 목표

1. 이 카테고리를 세 부류(etcd / 메시징·스트리밍 / 분산 DB)로 가르고 전수 지도를 그립니다
2. etcd가 K8s의 어떤 요구(선형화 읽기·watch·리스)를 만족시키는지, 왜 그것이 Raft여야 했는지 압니다
3. 메시징 계보를 구분합니다 — 큐(NATS core)·스트림(Kafka/Pulsar/JetStream)·이벤트 표준(CloudEvents)
4. "스테이트풀을 K8s에" 판단 프레임(오퍼레이터 Level × 스토리지 × 팀 역량)을 세웁니다
5. kind에서 etcd의 watch·리스를 직접 관찰하고, NATS로 큐와 스트림의 차이를 실측합니다

## 선행: 01(범례), k8s(etcd·StatefulSet), 05(스토리지), 08(오퍼레이터 Level) · 도구: kind, kubectl, helm, etcdctl
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md) — 지도 본체
2. [lab-01-category-census.md](./lab-01-category-census.md) — 전수 목록·부류 분류
3. [lab-02-etcd-and-nats.md](./lab-02-etcd-and-nats.md) — etcd의 watch/lease, NATS의 큐 vs 스트림
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2h
