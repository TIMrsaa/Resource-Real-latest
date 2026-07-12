# 자가 점검 퀴즈

**Q1.** Kyverno가 OPA(31)와 정반대로 택한 설계 결정은? 그 강점과 대가는?

**Q2.** Kyverno의 네 규칙 타입과 각각의 역할은?

**Q3.** generate가 왜 Kyverno의 독특한 강점인가요? validate와 어떻게 다른가?

**Q4.** mutate와 validate의 접근 차이는? mutate가 GitOps와 부딪히는 지점은?

**Q5.** "정책이 K8s 리소스"라는 것의 실무 의미 셋은?

**Q6.** verifyImages는 cicd 21의 무엇인가요? OPA와 어떻게 다른가?

**Q7.** K8s 코어의 VAP가 정책 지형을 어떻게 바꾸나요? OPA·Kyverno는 무엇으로 차별화되나요?

**Q8.** generate/mutate가 만드는 "소유권" 문제와, 그것을 다루는 원칙은?

---

## 정답

**A1.** OPA는 rego(전용 언어)로 범용성(K8s·CI·앱·Terraform)을 얻고 학습 곡선을 대가로 치렀다면, Kyverno는 정책을 K8s YAML(익숙한 형식)로 써서 진입 장벽을 낮추고 K8s 전용이라는 제약을 대가로 택했습니다. 강점: 새 언어를 안 배우고 K8s를 아는 사람이 kubectl로 정책을 배포·조회·GitOps 관리하며, 서비스 팀이 직접 정책을 쓸 수 있습니다(31 사고 사례의 rego 병목 해소). 대가: K8s 밖(CI·앱 인가·Terraform)에서 못 쓰고, 복잡한 로직 표현이 rego보다 제한적입니다.

**A2.** validate(검사 — 규칙 위반 시 거부/기록, pattern·deny·cel로), mutate(변형 — admission에서 리소스를 수정, 기본값·라벨·사이드카 주입), generate(생성 — 정책이 리소스를 만듭니다, 예: 새 네임스페이스에 기본 NetworkPolicy), verifyImages(서명 검증 — cosign keyless/key로 이미지 서명 확인, cicd 21). validate·mutate는 admission webhook에서, generate·재평가는 백그라운드 컨트롤러에서.

**A3.** generate는 정책이 리소스를 **만듭니다** — "모든 네임스페이스에 default-deny NetworkPolicy가 있어야 한다"를 validate로 하면 없을 때 위반을 알려줄 뿐이지만, generate로 하면 없으면 자동으로 만듭니다(선언 → 실현). synchronize: true면 누가 지워도 재생성합니다. 이것은 OPA/Gatekeeper가 나중에 제한적으로 추가한 영역으로 Kyverno의 독특한 강점이며, 테넌트 온보딩 자동화(네임스페이스 기본 리소스 생성) 같은 데 쓰입니다.

**A4.** validate는 규칙 위반 시 거부합니다("non-root가 아니면 거부"), mutate는 거부 대신 리소스를 고쳐서 통과시킵니다("non-root로 만들어서 통과", 기본값·사이드카 주입). GitOps와 부딪히는 지점: mutate가 admission에서 리소스를 바꾸므로 apply한 것과 실제 생성된 것이 달라지고(15의 Helm 3-way 병합 문제와 동형), GitOps 컨트롤러(ArgoCD)가 그 차이를 OutOfSync로 감지해 계속 diff가 생깁니다 — ignoreDifferences로 mutate 주입 필드를 무시해야 합니다(16의 필드 소유권).

**A5.** ① GitOps 관리(14): 정책이 CRD라 kubectl apply·Git 저장·버전 관리·PR 리뷰가 가능합니다. ② 감사: 위반이 PolicyReport CRD로 생성되어 `kubectl get policyreport -A`로 조회(07의 audit). ③ 접근 제어: RBAC로 누가 정책을 만들 수 있는지 제어(24의 거버넌스). 08의 오퍼레이터 패턴(CRD + 컨트롤러)이 정책에 적용된 것으로, OPA의 외부 결정 엔진과 대비되는 "K8s에 녹아든 정책 컨트롤러"다.

**A6.** cicd 21에서 배운 admission 이미지 서명 검증(cosign keyless로 "이 이미지가 이 저장소의 이 워크플로가 서명했나"를 확인)이 Kyverno의 규칙 타입으로 내장된 것입니다. OPA/Gatekeeper는 이미지 서명 검증을 별도로 구성해야 하지만 Kyverno는 verifyImages로 내장 지원하며(keyless subject·issuer·rekor 설정), "증명이 게이트"(21)를 K8s admission에 통합합니다.

**A7.** K8s 1.30+의 ValidatingAdmissionPolicy(VAP)는 CEL 기반 admission 정책을 코어 기능으로 제공해 외부 엔진 없이 단순 검사(필드 존재·값 비교)를 할 수 있게 합니다 — "검사"의 상당 부분이 코어로 이동합니다. 그래서 OPA·Kyverno는 검사 이상으로 차별화됩니다: Kyverno는 mutate·generate·verifyImages·정책 라이브러리(K8s 리소스 조작), OPA는 다영역(CI·Terraform·앱 인가)·복잡 로직(rego 표현력). 선택 시 "단순 검사면 VAP로 충분한가"를 먼저 묻고, 그 이상이 필요할 때 엔진을 고릅니다.

**A8.** generate는 리소스를 만들고 mutate는 리소스를 바꾸므로, 그 순간 정책 엔진이 그 리소스(또는 필드)의 "주인"이 됩니다. 그런데 K8s에는 이미 주인이 여럿 있습니다 — GitOps(ArgoCD), HPA, 다른 컨트롤러. 경계를 안 그리면 주인들이 싸웁니다(사고 사례: Kyverno generate NetworkPolicy vs ArgoCD가 무한 루프). 원칙: ① generate가 만드는 리소스와 GitOps가 관리하는 리소스의 경계를 명확히(겹치지 않게). ② mutate 주입 필드는 GitOps의 ignoreDifferences로 무시(16의 필드 소유권). ③ "누가 이 리소스의 주인인가"를 문서화 — 정책 엔진 도입은 소유권 지도에 새 주인을 추가하는 것입니다.
