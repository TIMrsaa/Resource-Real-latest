# 32 — Pod 보안: PSA, securityContext, user namespaces

> 고급 트랙 졸업 모듈. 모듈 01의 "컨테이너는 격리된 프로세스일 뿐"이라는 사실에서 출발해 — 그 격리를 단단히 조이는 모든 손잡이: Pod Security Admission, capabilities, seccomp, user namespaces.

## 학습 목표

1. 컨테이너 탈출의 공격면과 방어 계층을 그립니다
2. securityContext의 핵심 필드(runAsNonRoot, capabilities, seccomp, readOnlyRootFilesystem)를 다룹니다
3. Pod Security Admission(privileged/baseline/restricted)을 ns에 적용하고 위반을 체험합니다
4. restricted를 통과하는 "모범 Pod" 템플릿을 만듭니다
5. user namespaces(hostUsers: false)로 "컨테이너 root ≠ 호스트 root"를 검증합니다

## 선행: 모듈 01, 11, 23 · 환경: 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-securitycontext.md](./lab-01-securitycontext.md) — 손잡이 하나씩 잠그기
3. [lab-02-psa-userns.md](./lab-02-psa-userns.md) — PSA 적용 + user namespaces
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
**고급 수료**: 모듈 21~32 퀴즈 재점검 후 실무(04-production)로.
