# 26 — actions/runner에 기여하기: 내 잡을 실행하던 그 프로그램 안으로

> 03에서 실행 모델의 소비자로, 08에서 러너의 운영자로, 18에서 액션의 생산자로 살았습니다 — 이제 러너 **자체**의 개발자로 들어갑니다. actions/runner는 뜻밖에도 C#(.NET)으로 쓰인 크로스플랫폼 프로그램이고(Azure Pipelines 에이전트의 후손), Listener(롱폴 대기)와 Worker(잡 실행)의 2프로세스 구조입니다. 그리고 이 생태계에는 문이 네 개입니다 — runner(C#), toolkit(TypeScript, 18에서 사용), runner-images(호스티드 러너 이미지), ARC(Go, 08에서 운영) — 언어와 난이도가 달라, 자기에게 맞는 문을 고르는 것 자체가 이 모듈의 내용입니다.

## 학습 목표

1. 러너의 2프로세스 구조(Listener/Worker)와 잡 메시지의 여정을 소스에서 추적합니다
2. `_diag` 로그를 "러너 개발자의 눈"으로 읽습니다 — 03·25의 트러블슈팅이 소스 수준이 됩니다
3. 소스에서 러너를 빌드해 내 저장소에 등록하고, 스텝 하나가 핸들러로 실행되는 경로를 밟습니다
4. 생태계 4저장소(runner/toolkit/runner-images/ARC)의 기여 난이도 지도를 그리고 내 문을 고릅니다
5. GitHub이 주도하는 저장소의 현실(로드맵 우선, 외부 PR 보수적)을 알고 전략적으로 기여합니다

## 선행: 03(실행 모델 — 필수), 08(ARC 운영), 18(toolkit 사용), k8s 41·45(빌드·첫 PR) · 도구: .NET SDK 8+, git, gh, Node 20
## 비용: 없음 (로컬 빌드 + 무료 저장소)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-build-and-trace.md](./lab-01-build-and-trace.md) — 소스 빌드, 등록, 잡 실행 추적
3. [lab-02-choose-door-and-pr.md](./lab-02-choose-door-and-pr.md) — 4저장소 이슈 탐색, 기여 전략, 첫 PR
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 3h
