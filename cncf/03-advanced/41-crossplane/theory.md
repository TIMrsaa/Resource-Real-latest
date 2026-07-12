# 이론 — 컨트롤 플레인, 4층 모델, Terraform 대비, Composition, GitOps, 판단

> **🌱 17세 눈높이 비유: 자동 온도조절기 vs 한 번 트는 에어컨**
> - **Terraform(한 번 트는 에어컨)** = "지금 24도로 맞춰" 버튼을 누름 → 24도로 맞추고 끝. 누가 창문을 열어 더워져도(드리프트) 다시 누를 때까지 모름
> - **Crossplane(자동 온도조절기)** = "24도 유지"를 설정 → 계속 온도를 재고 벗어나면 자동으로 맞춤 (08의 조정 루프)
> - **K8s를 컨트롤 플레인으로** = 온도조절기(K8s)가 에어컨뿐 아니라 보일러·환풍기(클라우드 RDS·S3·VPC)까지 다 관리
> - **Composition(집 전체 모드)** = "취침 모드" 버튼 하나 = 온도+조명+커튼 세트 (개발자는 버튼만, 내부 5개 장치는 플랫폼 팀이 구성)
> - **핵심** = "맞춰라(명령)"가 아니라 "이 상태를 유지하세요(선언)" — 그리고 그 대상이 인프라 전체

---

## 1. 컨트롤 플레인이라는 발상 (08의 확장)

```
08의 조정 루프:
  원하는 상태(spec) ↔ 실제 상태(status)를 컨트롤러가 계속 맞춤
  대상: Pod, Deployment (클러스터 안)

Crossplane:
  같은 조정 루프, 대상만 확장
  대상: RDS·S3·VPC·GCP·Azure 리소스 (클러스터 밖, 클라우드 API)

  kind: RDSInstance          # 원하는 상태: RDS 하나
  spec: { class: db.t3.micro }
  → Crossplane 컨트롤러가 AWS API 호출 → 실제 RDS 생성
  → 드리프트(콘솔에서 변경) 감지 → 다시 맞춤

★ "K8s API = 범용 컨트롤 플레인"
  CRD로 무엇이든 표현하고, 컨트롤러로 무엇이든 조정
  → K8s가 컨테이너를 넘어 "모든 것의 조정자"
```

## 2. 4층 모델

```
① Provider (공급자)
   클라우드별 컨트롤러 패키지
   provider-aws, provider-gcp, provider-azure...
   → 해당 클라우드 API를 아는 컨트롤러 + CRD 묶음
   설치: kind: Provider (Crossplane이 컨트롤러를 배포)

② Managed Resource (관리 리소스, MR)
   실제 클라우드 리소스 하나 = CR 하나 (1:1)
   kind: RDSInstance, kind: Bucket, kind: VPC
   → 가장 낮은 수준 (클라우드 리소스와 직접 대응)
   → Provider가 이 CR을 조정해 실제 리소스 생성

③ Composition + XRD (조합·추상 정의)
   XRD(CompositeResourceDefinition): 새 추상 API 정의
     예: kind: XPostgreSQLInstance (내가 만든 타입)
   Composition: 그 추상이 어떤 MR들로 구성되는지
     XPostgreSQLInstance → RDSInstance + SecurityGroup + SubnetGroup
   → 플랫폼 팀이 "황금 경로"를 API로 (47)

④ Claim (요청)
   개발자가 네임스페이스에서 추상을 요청
   kind: PostgreSQLInstance (Composite의 네임스페이스판)
   spec: { parameters: { size: small } }
   → Composition이 뒤에서 여러 MR을 생성
   → 개발자는 내부 구성을 몰라도 됨 (셀프서비스)
```

## 3. 층별 흐름 (한눈에)

```
개발자:        Claim (PostgreSQLInstance, size:small)
                 ↓  (플랫폼 팀이 정의한)
추상 정의:     XRD + Composition
                 ↓  (조합)
관리 리소스:   RDSInstance + SecurityGroup + SubnetGroup (MR 3개)
                 ↓  (Provider가 조정)
Provider:      provider-aws가 AWS API 호출
                 ↓
실제:          AWS에 RDS·SG·Subnet 생성 + 지속 조정

★ 개발자는 맨 위(Claim)만, 플랫폼 팀은 중간(Composition)을,
  Provider는 맨 아래(클라우드 API)를 — 관심사 분리 (47의 핵심)
```

## 4. Terraform 대비 — 핵심 트레이드오프

```
                 Terraform              Crossplane
방식             명령형 apply(일회성)    선언형 + 지속 조정
드리프트         다음 apply까지 방치     자동 감지·교정
상태 저장        state 파일(별도 관리)   K8s etcd(CR의 status)
실행             CI/CD에서 apply         컨트롤러가 상시
추상화           모듈                   Composition/XRD
GitOps           별도 파이프라인 필요     기존 ArgoCD/Flux에 얹힘(14·15)
RBAC             자체                   K8s RBAC 그대로
생태계           방대(수천 provider)     성장 중(주요 클라우드)
운영 부담        state 관리·잠금         K8s 클러스터 운영
성숙도           매우 성숙               상대적으로 젊음

★ 대체가 아니라 다른 트레이드오프:
  Terraform: 단순·방대한 생태계·널리 검증, 하지만 일회성·드리프트 방치
  Crossplane: 지속 조정·GitOps 통합·K8s 네이티브, 하지만 K8s 운영 부담·성숙도
  → 조직의 K8s 성숙도, GitOps 채택도, 셀프서비스 필요에 따라 선택
```

## 5. GitOps 결합 (14·15의 확장)

```
Crossplane 리소스 = 그냥 K8s 오브젝트
  → ArgoCD/Flux가 앱처럼 인프라도 조정

Git 저장소:
  apps/           # 앱 매니페스트 (14·15)
  infra/
    database.yaml # kind: PostgreSQLInstance (Crossplane Claim)
    bucket.yaml   # kind: Bucket

ArgoCD가 infra/도 sync
  → 인프라 변경도 PR → 머지 → 자동 조정
  → "앱도 인프라도 Git이 진실의 원천" (14의 GitOps 원리를 인프라로)

★ Terraform은 별도 파이프라인(terraform plan/apply)이 필요하지만
  Crossplane은 기존 GitOps에 그대로 얹힙니다 — 이것이 큰 채택 이유
```

## 6. 책임과 한계 (오해 방지)

```
K8s가 인프라 컨트롤 플레인이 되면:
  + 통합(하나의 API·RBAC·GitOps)
  + 지속 조정(드리프트 자동 교정)
  - K8s 클러스터가 SPOF (컨트롤 플레인 다운 = 조정 중단)
    → 관리 클러스터의 HA·백업이 인프라 전체의 안정성
  - Crossplane 자체 학습·운영 부담
  - Composition 설계 역량 필요 (잘못 짜면 추상이 새는 추상)

성숙도:
  주요 클라우드 Provider는 성숙, 일부 리소스는 미지원·베타
  Terraform provider를 Crossplane으로 감싸는 방식(Upjet 생성)도 있음
```

## 7. 소스/도구에서 확인하기

- Crossplane: https://docs.crossplane.io — providers, compositions, XRD, claims
- provider-nop: 실제 클라우드 없이 개념 실습용 (lab에서 사용)
- Upjet: Terraform provider → Crossplane provider 생성
- 08(오퍼레이터·조정)·14·15(GitOps)·47(플랫폼 엔지니어링) 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| Crossplane 발상? | K8s API = 범용 컨트롤 플레인 (08의 조정을 인프라로) |
| 4층? | Provider(공급자)·Managed Resource(리소스 1:1)·Composition/XRD(추상)·Claim(요청) |
| Terraform 차이? | 명령형·일회성 vs 선언형·지속 조정(드리프트 자동 교정) |
| 상태 저장? | Terraform=state 파일, Crossplane=K8s etcd(CR status) |
| Composition 가치? | 플랫폼 팀이 황금 경로를 추상 API로 (47) |
| GitOps? | CR이라 ArgoCD/Flux가 인프라도 조정 (14·15 확장) |
| 한계? | K8s가 SPOF, 운영 부담, Composition 설계 역량 |
| 선택 기준? | K8s 성숙도·GitOps 채택·셀프서비스 필요 → 대체 아닌 트레이드오프 |
