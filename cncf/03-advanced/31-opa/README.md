# 31 — OPA 심층: 정책을 코드로, 어디서나

> 07의 보안 시간선에서 "관통하는 정책 엔진", cicd 24에서 conftest로, cicd 21에서 admission으로 만난 그것. OPA(Open Policy Agent)의 핵심 통찰은 **정책 결정을 애플리케이션에서 분리하는 것**입니다 — 앱은 "이 작업을 허용할까요?"를 OPA에 묻고, OPA는 rego로 쓰인 정책으로 답합니다. 이 모듈은 그 rego 언어(선언적 정책의 사고법), OPA의 배포 형태(라이브러리·사이드카·Gatekeeper), 그리고 왜 하나의 엔진이 K8s admission·CI·앱 인가·Terraform을 모두 덮는지를 팝니다. 32(Kyverno)와 대비해 "범용 rego vs K8s 네이티브"의 선택 기준을 완성합니다.

## 학습 목표

1. OPA의 결정 분리 모델(정책 질의/응답)과 배포 형태(라이브러리·서버·Gatekeeper)를 압니다
2. rego의 사고법(선언적, 규칙 = 참이 되는 조건)을 익히고 정책을 작성합니다
3. Gatekeeper(K8s admission)의 ConstraintTemplate/Constraint 모델을 이해합니다
4. 한 정책 엔진이 여러 영역(admission·CI·앱 인가)을 덮는 것을 확인합니다
5. OPA vs Kyverno(32)의 설계 차이와 선택 기준을 압니다

## 선행: 07(정책 엔진), cicd 24(conftest·Policy as Code), cicd 21(admission) · 도구: kind, kubectl, opa, conftest
## 비용: 없음 (kind + opa CLI)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-rego-thinking.md](./lab-01-rego-thinking.md) — rego 사고법, 정책 작성·테스트
3. [lab-02-gatekeeper-and-domains.md](./lab-02-gatekeeper-and-domains.md) — Gatekeeper, 여러 영역, Kyverno 대비
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
