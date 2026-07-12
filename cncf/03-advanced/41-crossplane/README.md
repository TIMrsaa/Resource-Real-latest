# 41 — Crossplane: 클러스터를 넘어 인프라를 다스리는 컨트롤 플레인

> 지금까지 K8s는 "컨테이너를 굴리는 오케스트레이터"였습니다. Crossplane은 그 관점을 뒤집습니다 — **K8s API를 범용 컨트롤 플레인으로 삼아 클라우드 인프라(RDS·S3·VPC)까지 선언형으로 관리**합니다. 08의 오퍼레이터·CRD, 14·15의 GitOps, 39·40의 오퍼레이터 패턴이 여기서 "인프라 전체"로 확장됩니다. Crossplane은 Terraform(명령형 프로비저닝)과 대비되는 "지속적 조정(continuous reconciliation)" 방식이며, 플랫폼 팀이 개발자에게 **셀프서비스 인프라 API**를 제공하는 도구입니다. 이 모듈은 Provider·Managed Resource·Composition·Claim의 4층을 파고, 42(Backstage)·47(플랫폼 엔지니어링)으로 이어지는 "내부 개발자 플랫폼"의 인프라 축을 세웁니다.

## 학습 목표

1. Crossplane이 K8s API를 범용 컨트롤 플레인으로 쓰는 발상(08의 조정 루프를 인프라로)을 압니다
2. 4층 모델(Provider·Managed Resource·Composition·Claim)과 각 역할을 압니다
3. Terraform(명령형·일회성 apply)과 Crossplane(선언형·지속 조정)의 차이와 트레이드오프를 압니다
4. Composition으로 플랫폼 팀이 개발자에게 추상 API(XRD)를 제공하는 방식을 압니다
5. GitOps(14·15)와 Crossplane이 결합해 "인프라도 Git으로 조정"되는 그림을 압니다

## 선행: 08(오퍼레이터·CRD·조정 — 필수), 14·15(GitOps), 39·40(오퍼레이터 패턴) · 도구: kind, kubectl, helm
## 비용: 없음 (kind + provider-nop/fake로 개념 실습, 실제 클라우드 불필요)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-provider-and-managed-resource.md](./lab-01-provider-and-managed-resource.md) — Provider, Managed Resource, 조정
3. [lab-02-composition-and-platform-api.md](./lab-02-composition-and-platform-api.md) — Composition·XRD·Claim, 플랫폼 API
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
