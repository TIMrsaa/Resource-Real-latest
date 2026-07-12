# 34 — Harbor 심층: 레지스트리가 공급망의 관문이 되입니다

> 10의 지도에서 "레지스트리·아티팩트" 갈래, 07의 보안 시간선에서 빌드 전(공급망)과 배포 시점을 잇는 주민. Harbor는 단순 이미지 저장소가 아닙니다 — **레지스트리에 스캔·서명·정책·복제·RBAC를 통합**해 공급망 보안의 관문으로 만든 프로젝트입니다. cicd 21에서 배운 공급망 보안(서명·SBOM·admission)의 상당수가 Harbor 안에서 레지스트리 기능으로 통합됩니다. 이 모듈은 그 통합의 구조(하나의 레지스트리가 어떻게 여러 보안 기능을 담나), OCI 아티팩트의 확장(이미지 아닌 것도 저장), 그리고 레지스트리가 신뢰 경계인 이유를 팝니다.

## 학습 목표

1. Harbor의 아키텍처(코어 + 레지스트리 + 스캐너 + 잡서비스)와 프로젝트/RBAC 모델을 압니다
2. 취약점 스캔(Trivy 통합)과 배포 차단 정책(스캔 게이트)을 이해합니다
3. 이미지 서명(cosign/notation)과 서명 없는 이미지 pull 차단을 압니다
4. 복제(replication)와 프록시 캐시로 멀티 레지스트리·rate limit(cicd 25)을 다룹니다
5. OCI 아티팩트 확장(SBOM·Helm 차트·서명이 같은 레지스트리에)과 레지스트리의 신뢰 경계를 압니다

## 선행: 10(지도), 07(보안 시간선), cicd 04·21(이미지·공급망), 26(containerd 이미지) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-registry-with-security.md](./lab-01-registry-with-security.md) — 프로젝트·스캔·정책
3. [lab-02-replication-and-artifacts.md](./lab-02-replication-and-artifacts.md) — 복제·프록시 캐시·OCI 아티팩트
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
