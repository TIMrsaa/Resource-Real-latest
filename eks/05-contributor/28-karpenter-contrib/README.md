# 28 — Karpenter에 기여하기: 코어와 프로바이더의 두 저장소

> 17에서 Karpenter를 **사용자**로 해부했습니다. 이제 **개발자**로 들어갑니다. Karpenter는 CNCF 프로젝트(kubernetes-sigs/karpenter, 클라우드 중립 코어)와 AWS 프로바이더(aws/karpenter-provider-aws)로 나뉜 흥미로운 구조입니다 — 그 경계를 읽는 것이 첫 관문이고, 로컬에서 컨트롤러를 돌려 실제 클러스터의 Pending Pod에 반응시키는 것이 두 번째 관문입니다. k8s 41~45에서 배운 업스트림 기여의 문법이 여기서 실전이 됩니다.

## 학습 목표

1. 코어/프로바이더 2저장소 구조를 읽고 — **내 변경이 어느 쪽인지** 판정합니다
2. 코드베이스 지도를 그립니다: provisioning(시뮬레이터), disruption(consolidation), instancetype(가격·후보)
3. 로컬에서 Karpenter를 빌드하고 실제 클러스터를 상대로 **디버그 실행**합니다
4. 테스트 문화(ginkgo/gomega, fake client, e2e)를 익히고 테스트를 먼저 씁니다
5. 첫 PR을 냅니다 — 좋은 첫 이슈 찾기부터 리뷰 대응까지

## 선행: eks 17(Karpenter 사용자 지식 — 필수), k8s 41(빌드), 42(코드투어), 44(테스트), 45(첫 PR) · 도구: Go 1.23+, git, gh
## 환경: 로컬 개발 + 공유 EKS(디버그 대상) — 클러스터에 실제 노드가 생길 수 있으니 limits 주의

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-build-and-debug.md](./lab-01-build-and-debug.md) — 빌드, 로컬 실행, 결정 과정 추적
3. [lab-02-test-and-pr.md](./lab-02-test-and-pr.md) — 테스트 작성, 첫 PR 워크플로
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 3h
