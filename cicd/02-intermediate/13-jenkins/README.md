# 13 — Jenkins: 가장 오래된 도구에서 배우는 것

> Jenkins(2011~, Hudson부터면 2005~)는 이 파트에서 가장 오래된 도구입니다. "요즘 누가 Jenkins를 쓰나"는 절반만 맞습니다 — 여전히 수많은 조직의 CI 심장이고, 그 이유(플러그인 생태계, 온프레 통제, 이식 비용)를 아는 것이 실무의 현실입니다. 이 모듈은 Jenkins를 최신 관점(Pipeline as Code, Jenkins on K8s)으로 배우고, 레거시 Jenkins를 현대 CI로 **마이그레이션하는 판단**을 다룹니다. 중급 트랙 졸업 모듈.

## 학습 목표

1. Jenkinsfile(Declarative/Scripted Pipeline)을 앞의 도구 지식으로 읽습니다
2. Jenkins의 아키텍처(controller/agent)와 그것이 K8s에서 도는 법(Kubernetes plugin)을 압니다
3. 플러그인 생태계의 힘과 그 대가(공급망·유지보수 부채)를 이해합니다
4. 공유 라이브러리(Shared Library)로 파이프라인을 재사용합니다 (06의 대응)
5. 레거시 Jenkins → 현대 CI 마이그레이션의 판단 기준과 전략을 세웁니다

## 선행: 03·06(Actions), 12(이식성), k8s 중급(Jenkins on K8s) · 도구: Docker(로컬 Jenkins) 또는 개념
## 비용: 로컬 Docker 무료

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-jenkinsfile.md](./lab-01-jenkinsfile.md) — Pipeline as Code, 이식성 확인
3. [lab-02-k8s-and-migration.md](./lab-02-k8s-and-migration.md) — Jenkins on K8s, 마이그레이션 판단
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
