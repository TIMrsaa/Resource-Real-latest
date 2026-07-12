# 16 — ArgoCD 심층: 규모, 멀티클러스터, 그리고 거버넌스

> cicd 14에서 reconcile 루프를 배웠고, cicd 27에서 소스를 열었습니다. 이 모듈은 **세 번째 각도** — 프로젝트를 조직 규모로 운영할 때 드러나는 것들입니다: 수천 개 Application에서 컨트롤러가 왜 느려지는가(샤딩·캐시·리스트 부하), 클러스터 100개를 어떻게 붙이는가(멀티클러스터 아키텍처와 그 한계), 팀 50개가 한 ArgoCD를 쓸 때 무엇이 필요한가(AppProject·RBAC·app-of-apps). 그리고 08의 사다리에서 3단(배달)의 대표 주자로서 Flux(17)와 무엇이 다른지의 근거를 만듭니다.

## 학습 목표

1. 컴포넌트별 부하 특성(application-controller/repo-server/redis)과 확장 지점을 압니다
2. 샤딩·`--repo-server-timeout`·캐시 튜닝 등 규모 운영의 손잡이를 압니다
3. 멀티클러스터 아키텍처 3형태(중앙집중/허브-스포크/클러스터별)의 트레이드오프를 판단합니다
4. ApplicationSet 생성기들과 app-of-apps 패턴으로 수백 앱을 선언적으로 관리합니다
5. AppProject·RBAC로 멀티팀 경계를 세웁니다 (cicd 24의 거버넌스를 배달 층에)

## 선행: cicd 14(필수), cicd 27(소스 구조), 08(사다리), 15(Helm) · 도구: kind, kubectl, helm, argocd CLI
## 비용: 없음 (kind 2개)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-scale-and-multicluster.md](./lab-01-scale-and-multicluster.md) — 부하 특성, 두 번째 클러스터 등록
3. [lab-02-appset-and-governance.md](./lab-02-appset-and-governance.md) — ApplicationSet, AppProject, RBAC
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 3h
