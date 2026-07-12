# 29 — amazon-vpc-cni-k8s에 기여하기: 가장 깊은 곳으로

> 07에서 ipamd의 IP 회계를, 16에서 고갈의 방정식을, 18에서 veth와 host route를 배웠습니다. 그 모든 코드가 하나의 저장소에 있습니다 — `aws/amazon-vpc-cni-k8s`. 두 개의 바이너리(ipamd 데몬 + CNI 플러그인), Linux 네트워킹 네임스페이스, EC2 API의 경계. EKS에서 가장 물리에 가까운 코드이며, 가장 많은 사용자가 매일 의존하는 코드입니다. 커리큘럼의 마지막 모듈답게, 여기서 우리는 **Pod의 첫 패킷이 태어나는 자리**를 읽고 고칩니다.

## 학습 목표

1. 두 바이너리의 역할 분담(ipamd 데몬 / CNI 플러그인)과 그 사이 gRPC 계약을 읽습니다
2. 07·16의 warm pool·prefix delegation 로직을 **datastore 코드**에서 확인합니다
3. 18의 veth·host route를 **plugin 코드**에서 확인합니다 — 그 몇 줄이 만든 세계
4. 빌드하고 단위 테스트를 돌립니다 — 네트워킹 코드를 클러스터 없이 검증하는 법
5. 기여 경로를 잡습니다: 로그·메트릭 개선 → 문서 → 버그픽스, 그리고 이 커리큘럼의 마무리

## 선행: eks 07(VPC CNI), 16(IP), 18(패킷 경로), 27(이슈), 28(PR 문법) · 도구: Go 1.23+, Docker, gh
## 환경: 로컬 개발 중심 — ⚠️ **공유 클러스터에 커스텀 CNI를 배포하지 말 것**(전 워크로드 영향)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-code-tour.md](./lab-01-code-tour.md) — 두 바이너리 해부, 이론과 코드 대조
3. [lab-02-build-test-contribute.md](./lab-02-build-test-contribute.md) — 빌드·테스트·기여 경로
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 3h
