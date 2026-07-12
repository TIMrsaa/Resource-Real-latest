# 23 — Admission: 웹훅과 ValidatingAdmissionPolicy(CEL)

> 모듈 21 파이프라인의 ③⑤ 단계에 **내 코드를 끼워넣는** 두 가지 방법: 웹훅(외부 서버 호출)과 CEL 정책(인프로세스 식 평가). 정책 엔진(Kyverno/OPA)의 원리이자 Operator의 반쪽.

## 학습 목표

1. Mutating/Validating 웹훅의 호출 규약(AdmissionReview)을 압니다
2. ValidatingAdmissionPolicy(CEL)로 웹훅 없이 정책을 구현합니다 (1.30+ GA)
3. failurePolicy의 양날(Fail=가용성 위험 / Ignore=보안 구멍)을 이해합니다
4. 웹훅이 클러스터 전체 장애가 되는 메커니즘과 방어 설계를 압니다
5. 실제 정책 3종(라벨 강제, latest 태그 금지, 리소스 한도)을 CEL로 작성합니다

## 선행: 모듈 21 · 환경: 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-cel-policies.md](./lab-01-cel-policies.md) — ValidatingAdmissionPolicy 3종 작성
3. [lab-02-webhook.md](./lab-02-webhook.md) — 미니 웹훅 서버 배포 + failurePolicy 실험
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
