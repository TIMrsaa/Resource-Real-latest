# 06 — Fluent Bit 파이프라인: 노드의 로그를 세상으로

> intermediate 트랙의 시작이자 로그 파이프라인의 본체. 02에서 완성한 "원천~노드 파일"의 다음 구간 — **Fluent Bit**이 노드마다(DaemonSet) 앉아 `/var/log/pods/`를 tail하고, CRI 포맷을 벗기고(02의 P/F!), JSON을 파싱하고(02의 구조화!), Kubernetes 메타데이터(네임스페이스·라벨)를 붙이고, 필터링해, 목적지로 내보내는 전 과정을 구축합니다. 파이프라인의 문법(INPUT→PARSER→FILTER→OUTPUT)과 함께, 운영의 본체인 **버퍼·백프레셔·재시도**(cncf 14에서 배운 유실의 물리를 설정으로 다루기)를 실습합니다. cncf 14가 Fluentd/Bit의 내부 원리였다면, 이 모듈은 K8s 위의 실전 배치입니다. 여기서 세운 파이프라인이 12(Loki)·13(CloudWatch)·18(OpenSearch)의 공통 앞단이 됩니다.

## 학습 목표

1. Fluent Bit 파이프라인 문법(INPUT·PARSER·FILTER·OUTPUT, tag/match 라우팅)을 읽고 씁니다
2. tail input + CRI 파서로 K8s 로그를 올바르게 수집합니다 (멀티라인·P/F 재조립 포함)
3. kubernetes 필터로 메타데이터를 붙이고, 필터로 소음을 거릅니다 (비용 통제의 첫 지점)
4. 버퍼(mem/filesystem)·백프레셔·재시도 설정의 의미를 유실 시나리오로 이해합니다
5. 수집기 자신의 관측(내장 메트릭)으로 "드롭·지연"을 감시합니다 (관측의 관측)

## 선행: 02(로그의 물리 — 필수), 05(지도), cncf 14(내부 원리 — 병행 권장) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-pipeline-basics.md](./lab-01-pipeline-basics.md) — DaemonSet 배포, CRI 파싱, k8s 메타데이터, 라우팅
3. [lab-02-buffer-and-backpressure.md](./lab-02-buffer-and-backpressure.md) — 버퍼·백프레셔·유실 재현과 방어
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2.5h
