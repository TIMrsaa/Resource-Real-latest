# 32 — Kyverno 심층: 정책을 K8s 리소스로

> 07의 보안 시간선에서 "배포 시점 K8s 네이티브 정책", cicd 21에서 서명 검증(verifyImages)으로 만난 그것. 31(OPA)이 rego라는 전용 언어로 범용성을 얻었다면, Kyverno는 정반대를 택합니다 — **정책을 K8s YAML로 씁니다.** 새 언어를 안 배우고, K8s 리소스처럼 정책을 다루며, validate를 넘어 mutate·generate·verifyImages까지 합니다. 이 모듈은 그 네 가지 능력, 정책이 K8s 리소스라는 것의 의미, 그리고 31과 나란히 놓았을 때의 최종 선택(범용 rego vs K8s 네이티브)을 완성합니다. cicd 24에서 예고한 "OPA vs Kyverno"의 결론입니다.

## 학습 목표

1. Kyverno의 아키텍처(admission webhook + 백그라운드 컨트롤러)와 정책이 CRD인 의미를 압니다
2. 네 가지 규칙 타입(validate/mutate/generate/verifyImages)을 각각 실습합니다
3. validate의 패턴 매칭과 CEL 표현식, mutate의 리소스 변형을 이해합니다
4. generate로 정책이 리소스를 만드는 것(예: 새 네임스페이스에 기본 NetworkPolicy)을 확인합니다
5. OPA vs Kyverno 최종 선택 기준과 함께 쓰는 패턴을 정리합니다

## 선행: 31(OPA — 필수 대비), 07(정책 엔진), cicd 21(verifyImages), cicd 24 · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-four-rule-types.md](./lab-01-four-rule-types.md) — validate/mutate/generate/verifyImages
3. [lab-02-opa-vs-kyverno.md](./lab-02-opa-vs-kyverno.md) — 31과 직접 대비, 최종 선택
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
