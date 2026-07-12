# 46 — 레퍼런스 플랫폼: 배운 것을 하나로 조립합니다

> beginner(01~10)에서 지형을, intermediate·advanced(11~45)에서 개별 프로젝트를 배웠습니다. 하지만 실무는 프로젝트 하나가 아니라 **여러 프로젝트가 맞물린 플랫폼**입니다. 이 모듈은 지금까지 배운 것을 하나의 **레퍼런스 아키텍처**로 조립합니다 — 관측(Prometheus·OTel·Grafana·Loki)·GitOps(Argo/Flux)·메시(Istio/Linkerd/Cilium)·보안(cert-manager·SPIFFE·Kyverno·Falco)·인그레스·시크릿을 층으로 쌓아, "프로덕션 K8s 플랫폼은 무엇으로 구성되나"의 전체 그림을 그립니다. 목표는 특정 스택 강요가 아니라 **층(layer)과 그 층을 채우는 선택지, 그리고 층 사이의 의존**을 이해하는 것 — 이것이 있어야 47(플랫폼 엔지니어링)과 48(비교 가이드)이 의미를 갖습니다.

## 학습 목표

1. 프로덕션 K8s 플랫폼의 층(관측·배포·메시·보안·인그레스·시크릿·데이터)을 압니다
2. 각 층을 채우는 프로젝트 선택지와 층 사이의 의존·순서를 압니다
3. 레퍼런스 아키텍처를 GitOps(14·15)로 부트스트랩하는 구조를 압니다
4. 층을 쌓을 때의 순서(무엇이 무엇에 의존)와 함정을 압니다
5. "완벽한 스택"이 아니라 조직 성숙도에 맞춘 점진적 도입을 판단합니다

## 선행: beginner·intermediate·advanced 전체 (특히 11·12·14·24·28·33·32·30 종합) · 도구: kind, kubectl, helm, argocd/flux
## 비용: 없음 (kind로 구조 — 실 클라우드는 규모만 다름)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-layered-bootstrap.md](./lab-01-layered-bootstrap.md) — 층별 부트스트랩, 의존 순서
3. [lab-02-integrated-platform.md](./lab-02-integrated-platform.md) — 층 통합, GitOps로 전체 조립
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
