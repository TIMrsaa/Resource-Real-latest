# 48 — 비교 가이드: 같은 자리를 두고 경쟁하는 것들 사이에서

> 커리큘럼 내내 우리는 "vs"를 만났습니다 — ArgoCD vs Flux(16·17), Istio vs Linkerd(24·25), OPA vs Kyverno(31·32), containerd vs CRI-O(26·27), Kafka vs NATS(38·40), Terraform vs Crossplane(41), CA vs Karpenter(44). 각 모듈에서 부분적으로 판단했지만, 이 모듈은 그것을 **한곳에 모아 판단의 방법론**으로 정리합니다. 목표는 "정답 목록"이 아닙니다 — 정답은 조직마다 다릅니다. 목표는 **비교의 축을 세우고(기능이 아니라 운영·팀·규모로), 자기 조직의 조건을 대입해 스스로 결론 내는 방법**입니다. production 트랙의 마무리이자, 아키텍트로서의 판단 훈련입니다.

## 학습 목표

1. 도구 비교의 방법론(기능표가 아니라 철학·운영 비용·팀 적합으로)을 세웁니다
2. 주요 대결 구도(GitOps·메시·정책·런타임·메시징·IaC·노드스케일)의 판단 축을 종합합니다
3. "기능 최대 vs 운영 최소"라는 반복 패턴을 인식합니다
4. 벤치마크·기능표의 함정과 PoC(개념 검증)의 올바른 설계를 압니다
5. 결정을 문서화(ADR)하고 재평가하는 규율을 압니다

## 선행: 해당 비교 대상 모듈들(16·17, 24·25, 31·32, 26·27, 38·40, 41, 44) — 이 모듈은 종합 · 도구: 개념 중심
## 비용: 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-comparison-matrix.md](./lab-01-comparison-matrix.md) — 대결 구도 종합, 판단 축 훈련
3. [lab-02-poc-and-adr.md](./lab-02-poc-and-adr.md) — PoC 설계, ADR(결정 기록)
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 1.5h
