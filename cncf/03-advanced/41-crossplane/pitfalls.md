# 흔한 함정과 실무 사고

## 흔한 함정 5선

### 1. Crossplane을 "더 나은 Terraform"으로만 봄
Crossplane과 Terraform은 대체 관계가 아니라 다른 트레이드오프입니다(theory 4절). Terraform의 방대한 생태계·단순한 state 모델·널리 검증된 성숙도를 버리고 Crossplane으로 옮기면, K8s 클러스터 운영 부담·상대적 미성숙·Composition 설계 역량이라는 새 비용을 집니다. 판단 기준은 "어느 게 더 좋냐"가 아니라 **"우리 조직이 K8s·GitOps에 얼마나 성숙했고 셀프서비스가 얼마나 필요한가"**입니다. K8s를 이제 막 도입한 팀에 Crossplane은 과합니다.

### 2. 관리 클러스터를 SPOF로 방치
Crossplane이 인프라를 조정한다는 것은 **그 클러스터가 죽으면 인프라 조정이 멈춘다**는 뜻입니다. 관리 클러스터(control plane cluster)를 앱과 같은 클러스터에 두거나 HA·백업 없이 운영하면, 인프라 전체의 안정성이 그 한 클러스터에 걸립니다. 관례: Crossplane은 **전용 관리 클러스터**에 두고, etcd 백업(k8s 36)·HA·복구 리허설을 인프라 수준으로 다룹니다. "인프라의 인프라"이므로 더 엄격히.

### 3. 새는 추상(leaky abstraction) Composition
Composition을 너무 얇게(MR을 거의 그대로 노출) 짜면 개발자가 결국 클라우드 세부를 알아야 해 추상의 이점이 없고, 너무 두껍게(모든 것을 숨김) 짜면 개발자가 필요한 조정(예: 인스턴스 크기 상향)을 못 해 플랫폼 팀에 매번 요청합니다. 좋은 Composition은 **개발자가 정말 신경 쓸 것(size·환경)만 파라미터로 열고 나머지는 안전한 기본값**으로 닫습니다 — 47의 "황금 경로는 넓어야 하되 난간이 있어야".

### 4. 드리프트 교정을 과신
Crossplane이 드리프트를 자동 교정하는 것은 강점이지만, **누가 콘솔에서 급히 바꾼 것을 Crossplane이 즉시 되돌려** 장애 대응을 방해할 수 있습니다. 긴급 상황에 콘솔에서 임시 조치했는데 Crossplane이 원복시켜 버리는 것. 대응: 긴급 변경은 반드시 CR(Git)에 반영하거나, 필요 시 조정을 일시 중지(`crossplane.io/paused` 애너테이션)합니다. **지속 조정은 평시엔 축복, 비상시엔 이해가 필요.**

### 5. Composition 변경의 폭발 반경 무시
Composition 하나를 모든 개발자가 공유하므로, 그것을 잘못 바꾸면 **모든 인스턴스가 동시에 재조정**됩니다. "모든 DB에 설정 추가"가 잘못되면 전 팀의 DB가 영향받습니다. Terraform 모듈보다 폭발 반경이 큽니다(지속 조정이라 즉시 전파). 관례: Composition 변경도 앱처럼 스테이징에서 검증하고, Composition을 버전(revision)으로 관리하며, 카나리(일부 인스턴스만 새 revision)로 점진 적용합니다.

## 실무 사고 사례: "삭제된 Claim이 프로덕션 DB를 지우다"

한 플랫폼 팀이 Crossplane으로 개발자 셀프서비스 DB(`AppDatabase` Claim → 실제 RDS)를 운영했습니다. GitOps(ArgoCD)로 각 팀의 Claim을 관리했습니다. 한 팀이 저장소를 리팩터링하며 디렉터리 구조를 바꿨는데, **ArgoCD가 옛 경로의 Claim을 "삭제됨"으로 인식**했습니다.

Crossplane은 Claim 삭제를 충실히 조정했습니다 — Composition이 만든 RDSInstance·백업버킷을 **finalizer로 정리**하며 실제 AWS RDS를 삭제하기 시작했습니다. 프로덕션 DB였습니다. 다행히 `deletionPolicy: Orphan`이 일부에 설정돼 있어 완전 삭제는 면했지만, 몇 개는 실제로 사라졌고 백업에서 복구해야 했습니다.

원인 분석:

1. **선언형의 양날** — Crossplane은 "Claim이 없으면 리소스도 없어야"를 충실히 따랐습니다. GitOps 실수가 곧 인프라 삭제로 직결됐습니다(14의 "Git이 진실의 원천"이 인프라에선 더 위험).
2. **`deletionPolicy` 미설정** — 중요 리소스는 `deletionPolicy: Orphan`(CR 삭제해도 실제 리소스 보존)이어야 했는데 기본값(Delete)이었습니다.
3. **삭제 보호 부재** — ArgoCD의 prune에 대한 가드(리소스 삭제 확인·`Prune=false` 애너테이션)가 없었습니다.

**교훈:**
- 인프라의 GitOps는 앱보다 **삭제가 훨씬 위험** — Git 실수 = 인프라 삭제
- 중요 리소스는 `deletionPolicy: Orphan` + 별도 백업 — Crossplane CR을 지워도 실제 데이터는 보존(39·40의 "복제는 백업 아님"과 같은 정신)
- ArgoCD prune 가드(`Prune=false`, 삭제 확인 훅), Composition에 삭제 보호
- **"K8s API = 컨트롤 플레인"은 강력하지만, 그 강력함이 실수도 즉시 인프라에 반영합니다** — 스테이트풀·인프라일수록 안전장치(백업·orphan·prune 가드)를 층층이

★ Crossplane은 08의 조정 루프를 인프라로 확장한 것 — 조정의 힘(자동·지속)과 위험(실수의 즉시 전파)을 함께 물려받습니다. 인프라는 앱보다 폭발 반경이 크므로, 41의 강력함은 그만큼의 규율(관리 클러스터 HA, orphan 정책, 변경 카나리)을 요구합니다.
