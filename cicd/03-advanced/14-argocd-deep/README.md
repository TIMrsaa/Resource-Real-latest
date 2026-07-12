# 14 — ArgoCD 심층: 배포를 push에서 pull로 뒤집습니다

> 지금까지의 CD는 전부 **push** 모델이었습니다 — 파이프라인이 클러스터 자격증명을 갖고 `kubectl apply`를 밀었습니다(07·10). GitOps는 이것을 뒤집습니다: 클러스터 안의 컨트롤러가 git을 **당겨와** 스스로 맞춥니다. 그 결과 파이프라인은 클러스터 자격증명이 필요 없어지고(보안), git이 유일한 진실이 되며(감사·롤백), 드리프트가 자동 교정됩니다. 이 모듈은 ArgoCD의 reconcile 루프를 해부하고, k8s 39(GitOps 원리)·eks 23(fleet)이 여기서 CI/CD로 수렴합니다.

## 학습 목표

1. push CD와 pull CD(GitOps)의 차이와, 그것이 바꾸는 보안·감사·롤백을 이해합니다
2. ArgoCD의 구조(Application CRD, reconcile 루프, sync/health)를 해부합니다
3. sync 정책(auto/selfHeal/prune), sync wave, hook을 설계합니다
4. ApplicationSet으로 fleet(eks 23)에 앱을 전개합니다
5. GitOps의 경계 문제(시크릿·이미지 태그 업데이트·CI와의 접점)를 압니다

## 선행: k8s 39(GitOps 원리·ArgoCD), eks 23(fleet), 04(불변 태그·다이제스트), 11(배포 전략) · 환경: 공유 EKS
## ⚠️ 비용: ArgoCD는 클러스터 내(무과금), 배포되는 워크로드만

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-reconcile-loop.md](./lab-01-reconcile-loop.md) — Application, drift 교정, sync 정책
3. [lab-02-appset-and-boundaries.md](./lab-02-appset-and-boundaries.md) — ApplicationSet fleet, 시크릿/이미지 경계
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2.5h
