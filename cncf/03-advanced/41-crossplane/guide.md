# 학습 가이드 — 컨트롤 플레인이라는 발상

## 관점의 전환

지금까지 40개 모듈에서 K8s는 "컨테이너를 굴리는 것"이었습니다. Crossplane은 이 관점을 확장합니다:

```
기존 관점: K8s = 컨테이너 오케스트레이터
Crossplane 관점: K8s API = 범용 컨트롤 플레인
  "무엇이든(클라우드 DB·버킷·네트워크) 원하는 상태를 선언하면
   조정 루프가 실제와 맞춘다"
```

08에서 배운 조정 루프(원하는 상태 ↔ 실제 상태를 계속 맞춤)를 떠올려라. Crossplane은 그 루프의 대상을 **Pod가 아니라 AWS RDS 인스턴스**로 넓힌 것입니다. `kind: RDSInstance`를 apply하면, Crossplane이 AWS API를 호출해 실제 RDS를 만들고, 드리프트가 생기면(누가 콘솔에서 바꾸면) 다시 맞춥니다.

## 왜 이게 강력한가 — 08의 반복이지만 규모가 다릅니다

```
08의 오퍼레이터: 앱(Ceph·Kafka)을 조정
Crossplane: 클라우드 인프라 전체를 조정
공통 원리: CRD(원하는 상태 표현) + 컨트롤러(조정 루프)
차이: 조정 대상이 클러스터 밖(클라우드 API)
```

39(Rook)·40(Strimzi)이 "오퍼레이터로 앱을 운영"했다면, Crossplane은 "오퍼레이터로 인프라를 운영"합니다. 같은 08의 원리가 스토리지→메시징→인프라로 계속 확장되는 것을 봅니다.

## Terraform과의 대비 — 핵심 논점

이 모듈에서 가장 중요한 비교입니다:

```
Terraform: 명령형에 가까운 프로비저닝
  terraform apply → 상태 파일과 비교해 변경 → 끝 (일회성)
  드리프트는 다음 apply까지 방치 (누가 콘솔에서 바꿔도 모름)

Crossplane: 선언형 + 지속 조정
  CR apply → 컨트롤러가 계속 실제와 맞춤 (드리프트 자동 교정)
  K8s 안에 있어 RBAC·GitOps·이벤트를 그대로 활용
```

둘 다 IaC(Infrastructure as Code)지만 철학이 다릅니다 — Terraform은 "실행하면 맞춘다", Crossplane은 "항상 맞춰져 있다". 이 차이(일회성 vs 지속)가 12장의 조정(reconciliation) 개념과 직결됩니다. 트레이드오프도 있습니다(theory에서): Crossplane은 K8s 운영 부담·성숙도, Terraform은 방대한 생태계·단순함.

## 플랫폼 엔지니어링의 씨앗 — Composition

Crossplane의 진짜 가치는 단순 프로비저닝이 아니라 **추상화**입니다:

```
플랫폼 팀이 Composition을 정의:
  "PostgreSQLInstance를 요청하면 → RDS + 보안그룹 + 서브넷그룹 + 파라미터그룹을
   한 세트로 만들어라"
개발자는 추상 API만 사용:
  kind: PostgreSQLInstance
  spec: { size: small }
  → 내부의 4개 리소스는 몰라도 됨
```

이것이 47(플랫폼 엔지니어링)의 핵심 — 플랫폼 팀이 "황금 경로(golden path)"를 API로 제공하고, 개발자는 셀프서비스로 인프라를 얻습니다. 42(Backstage)가 그 API의 UI라면, Crossplane은 그 API의 백엔드입니다.

## GitOps와의 결합 — 14·15의 확장

```
14·15: 앱 매니페스트를 Git → ArgoCD/Flux가 클러스터에 조정
+ Crossplane: 인프라 CR도 Git → 같은 GitOps로 인프라까지 조정
= "앱도 인프라도 Git이 진실의 원천"
```

Crossplane 리소스가 그냥 K8s 오브젝트이므로, ArgoCD가 앱을 배포하듯 인프라(RDS·S3)도 배포합니다 — Terraform은 별도 파이프라인이 필요했지만 Crossplane은 기존 GitOps에 얹힙니다. 이 통합이 Crossplane 채택의 큰 이유입니다.

## 이 모듈의 오해 방지

- Crossplane이 Terraform을 "대체"한다기보다 **다른 트레이드오프**입니다 (theory 참고)
- 실습은 실제 클라우드 없이 provider-nop/fake로 **개념**(조정·Composition)에 집중
- "K8s를 인프라 컨트롤 플레인으로"는 강력하지만 **K8s 자체가 SPOF가 되는** 책임도 따릅니다
