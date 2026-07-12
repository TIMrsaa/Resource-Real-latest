# 자가 점검 퀴즈

**Q1.** "K8s API = 범용 컨트롤 플레인"이라는 Crossplane의 발상은 08의 무엇을 확장한 것인가요?

**Q2.** Crossplane의 4층 모델과 각 역할은?

**Q3.** Terraform과 Crossplane의 핵심 차이(방식·드리프트·상태·GitOps)는? 대체가 아니라 무엇인가요?

**Q4.** XRD·Composition·Claim이 플랫폼 엔지니어링(47)에서 하는 역할은?

**Q5.** Crossplane이 GitOps(14·15)와 잘 결합하는 이유는? Terraform과 어떻게 다른가?

**Q6.** 관리 클러스터가 왜 특별히 신경 써야 하는 SPOF인가요?

**Q7.** `deletionPolicy: Orphan`은 왜 중요한가? 어떤 사고를 막는가요?

**Q8.** Composition 변경의 폭발 반경이 왜 Terraform 모듈보다 큰가?

---

## 정답

**A1.** 08의 조정 루프(원하는 상태 spec ↔ 실제 상태 status를 컨트롤러가 계속 맞춤)를 확장한 것입니다. 08에서는 조정 대상이 클러스터 안(Pod·Deployment)이었지만, Crossplane은 같은 조정 루프의 대상을 클러스터 밖 클라우드 인프라(RDS·S3·VPC)로 넓힙니다. `kind: RDSInstance`를 apply하면 컨트롤러가 AWS API로 실제 RDS를 만들고 드리프트를 교정합니다 — CRD(원하는 상태 표현)+컨트롤러(조정)라는 08의 원리 그대로, 대상만 "모든 것"으로 확장했습니다.

**A2.** ① Provider — 클라우드별 컨트롤러+CRD 패키지(provider-aws 등, 해당 클라우드 API를 아는 조정기). ② Managed Resource(MR) — 실제 클라우드 리소스와 1:1인 CR(RDSInstance·Bucket, 가장 낮은 수준). ③ Composition + XRD — XRD가 새 추상 API 타입을 정의하고 Composition이 그 추상을 어떤 MR들로 조합할지 정의(플랫폼 팀의 황금 경로). ④ Claim — 개발자가 네임스페이스에서 추상을 요청(size만 고르면 뒤에서 여러 MR 생성, 셀프서비스).

**A3.** 방식: Terraform은 명령형에 가까운 일회성 apply, Crossplane은 선언형+지속 조정. 드리프트: Terraform은 다음 apply까지 방치, Crossplane은 컨트롤러가 상시 감지·교정. 상태: Terraform은 state 파일(별도 관리), Crossplane은 K8s etcd(CR status). GitOps: Terraform은 별도 파이프라인(plan/apply) 필요, Crossplane은 CR이라 기존 ArgoCD/Flux에 얹힘. 대체가 아니라 **다른 트레이드오프** — Terraform은 방대한 생태계·단순·성숙, Crossplane은 지속 조정·GitOps 통합·K8s 네이티브지만 K8s 운영 부담·상대적 미성숙. 조직의 K8s 성숙도·셀프서비스 필요로 선택합니다.

**A4.** XRD는 플랫폼 팀이 개발자용 추상 API 타입(예: AppDatabase)을 정의 — 회사 도메인 어휘를 K8s API로. Composition은 그 추상이 실제로 어떤 MR들(DB+백업버킷+모니터링)로 구성되는지 정의 — 모범 구성(황금 경로)을 한 번 정의하면 모든 개발자가 같은 안전한 세트를 얻음. Claim은 개발자가 size만 골라 셀프서비스 — 내부 구성을 몰라도 됨. 결과적으로 인지 부하를 플랫폼 팀이 흡수하고 개발자는 도메인 언어로 셀프서비스합니다(47의 핵심 메커니즘, 42 Backstage가 그 UI).

**A5.** Crossplane 리소스가 그냥 K8s 오브젝트이기 때문입니다 — ArgoCD/Flux가 앱 매니페스트를 조정하듯 인프라 CR(RDS·S3)도 똑같이 조정합니다. Git에 인프라 CR을 커밋하면 PR→머지→자동 조정으로 "앱도 인프라도 Git이 진실의 원천"이 됩니다(14의 GitOps 원리를 인프라로 확장). Terraform은 별도 파이프라인(terraform plan/apply)과 state 관리·잠금이 필요하지만, Crossplane은 기존 GitOps에 그대로 얹힙니다 — 이 통합이 큰 채택 이유입니다.

**A6.** Crossplane이 인프라를 조정하므로, 그 관리 클러스터가 죽으면 인프라 조정 자체가 멈춥니다 — "인프라의 인프라"다. 앱과 같은 클러스터에 두거나 HA·백업 없이 운영하면 인프라 전체의 안정성이 그 한 클러스터에 걸립니다. 그래서 전용 관리 클러스터에 두고 etcd 백업(36)·HA·복구 리허설을 인프라 수준으로 더 엄격히 다뤄야 합니다.

**A7.** `deletionPolicy: Orphan`은 Crossplane CR(Claim/MR)을 삭제해도 실제 클라우드 리소스는 보존하게 합니다(기본값 Delete는 실제 리소스도 삭제). 이것이 막는 사고: GitOps 실수(경로 리팩터링으로 ArgoCD가 Claim을 "삭제됨"으로 인식)나 실수로 CR을 지웠을 때, Crossplane이 finalizer로 실제 프로덕션 DB를 삭제하는 것. 선언형의 양날("Claim이 없으면 리소스도 없어야")이 인프라에선 위험하므로, 중요 리소스는 Orphan+별도 백업으로 실제 데이터를 보호합니다(39·40의 "복제는 백업 아님"과 같은 정신).

**A8.** Composition 하나를 모든 개발자가 공유하고 Crossplane이 **지속 조정**하기 때문입니다. Composition을 잘못 바꾸면 모든 인스턴스가 즉시 재조정되며 변경이 전 팀에 동시 전파됩니다("모든 DB에 설정 추가"가 잘못되면 전 팀 DB 영향). Terraform 모듈은 각자 apply 시점에 반영되지만 Crossplane은 지속 조정이라 즉시 퍼집니다. 그래서 Composition 변경도 스테이징 검증·revision 버전 관리·카나리(일부 인스턴스만 새 revision)로 점진 적용해야 합니다.
