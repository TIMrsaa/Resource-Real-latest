# 13 — RPS 측정의 모든 것: 부하 생성과 해석의 과학

> "우리 서비스 몇 RPS까지 견뎌요?"에 숫자로 답하는 모듈. 부하를 **만들고**(k6/vegeta), **재고**(p99, 포화점), **해석합니다**(Little's Law, open vs closed 모델). 고급 트랙 전체(14~20)가 이 측정 위에서 논증됩니다 — 측정 없는 튜닝은 미신입니다.

## 학습 목표

1. RPS·throughput·goodput을 구분하고, 지연은 평균이 아니라 **분포(p50/p95/p99)** 로 읽습니다
2. Little's Law(L = λW)로 동시성·RPS·지연의 관계를 계산하고 실측으로 검증합니다
3. open 모델과 closed 모델의 차이, coordinated omission이 만드는 착시를 압니다
4. k6로 포화 곡선(throughput-latency)을 그리고 무릎(knee)을 찾습니다
5. 측정 환경 설계(부하기 위치·병목 분리·워밍업)를 체크리스트로 만듭니다

## 선행: k8s 06(requests/limits), 26(HPA — 여기선 끄고 측정), eks 08(ALB), 12(관측성) · 환경: 공유 EKS
## ⚠️ 공유 클러스터에서 부하는 **클러스터 안 대상에게만** — 외부 서비스에 쏘면 공격입니다

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-k6-baseline.md](./lab-01-k6-baseline.md) — 베이스라인, 램프업, 포화점 찾기
3. [lab-02-open-model-littles-law.md](./lab-02-open-model-littles-law.md) — open 모델, 착시 재현, 법칙 검증
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
