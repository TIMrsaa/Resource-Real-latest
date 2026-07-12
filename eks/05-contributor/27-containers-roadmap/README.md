# 27 — AWS에 영향 미치기: containers-roadmap과 피드백의 기술

> EKS는 오픈소스가 아닙니다 — 그런데 **공개 로드맵**이 있습니다. aws/containers-roadmap은 AWS 컨테이너 서비스팀이 이슈로 기능을 논의하고 우선순위를 정하는 곳이며, 우리가 실제로 개입할 수 있는 유일한 공식 통로입니다. 이 모듈은 "불평"을 "영향력"으로 바꾸는 기술입니다: 재현 가능한 이슈, 근거 있는 요청, 그리고 오픈소스 컴포넌트(vpc-cni·ALB 컨트롤러·Karpenter)로의 진짜 기여 경로 지도.

## 학습 목표

1. EKS 생태계의 오픈/클로즈드 경계를 정확히 그립니다 — 어디에 무엇을 제기할 것인가
2. containers-roadmap의 작동 방식(라벨·상태·+1의 의미)을 읽습니다
3. **좋은 이슈**를 씁니다 — 재현 절차, 영향 정량화, 대안 검토가 담긴 (실습)
4. 앞의 26개 모듈에서 만난 실제 마찰을 이슈 후보로 정리합니다
5. 기여의 사다리(피드백 → 문서 → 코드)를 설계하고 28·29로 넘깁니다

## 선행: eks 전 모듈(마찰의 경험이 재료입니다) · 도구: GitHub 계정, git
## 실습은 **드래프트 작성까지** — 실제 제출은 각자의 판단으로 (중복·품질 확인 후)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-read-the-roadmap.md](./lab-01-read-the-roadmap.md) — 로드맵 해부, 좋은 이슈/나쁜 이슈 감별
3. [lab-02-write-an-issue.md](./lab-02-write-an-issue.md) — 재현 가능한 이슈 드래프트 작성
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2h
