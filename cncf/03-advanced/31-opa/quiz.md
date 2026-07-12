# 자가 점검 퀴즈

**Q1.** OPA의 결정 분리 모델(PEP/PDP)을 설명하세요. 이 분리가 주는 이점 셋은?

**Q2.** rego의 선언적 사고를 명령형과 대비해 설명하세요. `deny[msg] { ... }`는 어떻게 여러 위반을 수집하나요?

**Q3.** input과 data의 차이는? OPA의 결정은 무엇들의 함수인가요?

**Q4.** Gatekeeper의 ConstraintTemplate과 Constraint의 관계는? enforcementAction의 값과 그 순서는?

**Q5.** 같은 rego 정책이 덮을 수 있는 영역 다섯 가지는? 07의 무엇을 실현하나요?

**Q6.** rego 정책을 테스트하는 이유와 방법은? Gatekeeper에서 테스트 없이 enforce하면?

**Q7.** OPA를 admission·앱 인가에 쓸 때의 성능·가용성 고려사항은?

**Q8.** OPA와 Kyverno의 강약점이 대칭인 이유와, 함께 쓰는 전형적 분담은?

---

## 정답

**A1.** PEP(Policy Enforcement Point)는 정책을 집행하는 곳(앱, K8s API 서버, CI)이고 PDP(Policy Decision Point)는 정책을 결정하는 곳(OPA)입니다. PEP가 "이 작업을 허용할까요?"를 input과 함께 PDP에 묻고, PDP가 rego 정책으로 "allow/deny + 이유"를 답하면 PEP가 그대로 집행합니다. 이점: ① 정책이 앱 코드에서 분리되어 언어 무관(어느 언어의 앱이든 같은 정책). ② 중앙 관리(정책의 단일 소스). ③ 감사 가능(정책이 명시적 코드로 존재). 그리고 하나의 PDP가 여러 PEP를 덮습니다.

**A2.** 명령형은 "순회하며 위반을 찾아 리스트에 추가"(어떻게 계산하나)이고, rego는 "위반은 이 조건이 참일 때 존재한다"(무엇이 참인가)를 선언합니다 — OPA가 조건 평가를 대신합니다. `deny[msg] { 조건들; msg := ... }`는 부분 규칙(partial set rule)으로, `input.spec.containers[_]`의 `[_]`가 모든 컨테이너를 순회하며 본문 조건이 모두 참인 경우마다 msg를 집합(set)에 추가합니다 — 명령형 루프 없이 모든 위반이 자동으로 모입니다.

**A3.** input은 그때그때의 질의(누가 무엇을 하려 하나 — user, action, resource, 검사 대상 오브젝트), data는 정책이 참조하는 배경 데이터(역할 매핑, 신뢰 레지스트리 목록, 허용 목록 등 상대적으로 정적인 것). OPA의 결정은 **input + data + rego 정책**의 함수입니다 — 같은 정책이라도 data(예: 신뢰 레지스트리)를 바꾸면 결정이 달라지므로, 정책 로직(rego)과 정책 데이터(data)를 분리해 관리합니다(lab-01 Step 4).

**A4.** ConstraintTemplate은 rego 정책 + 파라미터 스키마를 담은 재사용 템플릿으로, 적용 시 새 CRD(예: K8sRequiredLabels)를 만듭니다. Constraint는 그 템플릿의 인스턴스로 "어느 리소스에, 어떤 파라미터로" 구체적으로 적용합니다(같은 템플릿을 여러 Constraint로 다르게 적용 가능). enforcementAction: dryrun(위반 기록만) → warn(경고) → deny(차단) 순으로, 07·21의 audit→enforce 이행 곡선을 따라 dryrun으로 위반을 파악한 뒤 deny로 전환합니다.

**A5.** ① K8s admission(Gatekeeper — 배포 시점). ② CI(conftest — 매니페스트·IaC 검사, cicd 24). ③ 앱 인가(OPA 서버/라이브러리 — API 요청마다). ④ Terraform plan 검사(conftest — 인프라 변경 규정). ⑤ Envoy ext_authz(23 — 프록시 레벨 인가). (+Kafka·SQL·CI/CD 시스템 인가.) 07의 "관통하는 정책 엔진"을 실현합니다 — 조직이 rego 하나로 전 영역 정책을 통일하고, "prod에는 서명된 이미지만" 같은 정책을 admission·CI·런타임에서 같은 소스로 관리하는 정책의 단일 진실 소스(SSOT).

**A6.** rego 정책도 코드라 버그가 있습니다 — 조건을 잘못 써서 모든 것을 거부(배포 전면 중단)하거나 아무것도 안 잡을(정책이 장식) 수 있습니다. `opa test`로 부정 테스트("이것은 거부되어야 한다")와 긍정 테스트("이것은 통과해야 한다")를 작성해 정확성을 검증합니다(cicd 24의 규율). Gatekeeper에서 테스트 없이 잘못된 Constraint를 enforce로 켜면 정상 리소스 생성이 거부되어 클러스터가 마비될 수 있습니다(사고 사례: 30분간 전 클러스터 배포 중단) — 반드시 dryrun으로 검증 후 enforce.

**A7.** 성능: 복잡한 rego(중첩 순회·큰 data·무거운 정규식)는 평가가 느려지고, admission에서는 모든 API 요청이 Gatekeeper를 거치므로 클러스터 전체가 느려지며 webhook 타임아웃으로 요청이 실패할 수 있습니다. 앱 인가에서는 요청마다 rego 평가가 일어나 지연이 곧 사용자 경험입니다. 대응: 정책을 단순하게 유지, 큰 data는 인덱싱 고려, admission webhook의 failurePolicy(OPA가 죽으면 요청을 막을지[fail-closed] 통과시킬지[fail-open] — 21의 보안 대 가용성 선택)를 명시. 정책 엔진 자체가 성능·가용성 고려 대상입니다.

**A8.** OPA는 범용 rego(전용 언어, 학습 곡선 있지만 K8s·CI·앱·Terraform·Envoy 전 영역과 복잡 로직에 강함)이고, Kyverno는 K8s 네이티브 YAML(K8s 전용이지만 진입 쉬움, generate·mutate 강함) — 한쪽의 강점(범용성·복잡 로직)이 다른 쪽의 약점이고 그 반대도 성립해 대칭입니다. 전형적 분담: CI·Terraform·다영역 통일과 복잡 로직은 OPA(conftest·Gatekeeper), 팀별 K8s admission의 단순 정책(라벨·태그·리소스)은 Kyverno로 서비스 팀이 직접 YAML로 — rego 병목을 풀면서 각 도구를 강점에 배치합니다("도구의 강점은 그것을 쓸 수 있는 사람이 있을 때만 강점").
