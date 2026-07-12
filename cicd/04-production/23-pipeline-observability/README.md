# 23 — 파이프라인 관측: CI/CD도 프로덕션 시스템입니다

> 파이프라인이 느려지고 불안정해지는 것은 서비스 장애만큼 비쌉니다 — 사용자가 "전체 개발팀"이기 때문입니다. 그런데 대부분의 조직이 서비스에는 대시보드를 두면서 파이프라인은 "느낌"으로 운영합니다. 이 모듈은 01의 DORA 4지표를 측정 가능하게 만들고, 러너 풀을 큐 시스템으로(eks 13의 Little's Law 재등장!) 관찰하며, 빌드 시간을 critical path로 분석해 줄이고, 05의 flaky 격리를 운영 시스템으로 완성합니다.

## 학습 목표

1. 파이프라인 메트릭의 3계층(DORA/파이프라인/스텝)을 구분하고 각각 무엇을 결정하는 데 쓰는지 압니다
2. DORA 4지표를 실제 데이터(워크플로 이력)에서 계산합니다 — 그리고 측정의 함정(정의·게이밍)을 압니다
3. queue time을 러너 풀의 용량 신호로 읽습니다 — Little's Law(eks 13)의 CI판
4. 병렬 파이프라인의 전체 시간은 critical path가 정합니다 — 병목을 찾아 줄이는 순서를 압니다
5. flaky를 "재시도로 숨기기"가 아니라 측정·격리·소유권의 시스템(05)으로 관리합니다

## 선행: 01(DORA), 05(flaky 격리), 08(러너 풀), 19·20(캐시), eks 13(Little's Law) · 도구: gh, jq/python
## 비용: 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-measure-dora.md](./lab-01-measure-dora.md) — 워크플로 이력에서 DORA·큐·성공률 추출
3. [lab-02-optimize-and-flaky.md](./lab-02-optimize-and-flaky.md) — critical path 최적화 + flaky 탐지 리포트
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2.5h
