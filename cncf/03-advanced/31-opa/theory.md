# 이론 — 결정 분리 모델, rego, Gatekeeper, 다영역, Kyverno 대비

> **🌱 17세 눈높이 비유: 학교의 규정 심판**
> - **앱** = 각 교실 — "이 학생이 조퇴해도 되나요?"를 판단해야 합니다
> - **OPA** = 학교의 단일 규정 심판 — 교실이 물으면 규정집(rego)으로 답합니다("허용/거부 + 이유")
> - **rego** = 규정집의 언어 — "이런 경우 위반이다"를 선언적으로 (일일이 "이렇게 처리해라"가 아니라)
> - **결정 분리** = 각 교실이 자기만의 규정을 만들지 않고, 심판 한 명에게 위임 — 규정이 일관되고 바꾸기 쉽습니다
> - **어디서나** = 조퇴 심판, 시험 부정 심판, 동아리 예산 심판 — 같은 심판 체계로 (K8s admission·CI·앱 인가)
> - **Gatekeeper** = 학교 정문의 규정 심판 특화판 (K8s admission 전용)

---

## 1. 결정 분리 모델 — PDP와 PEP

```
PEP(Policy Enforcement Point): 정책을 '집행'하는 곳 (앱, K8s API 서버, CI)
PDP(Policy Decision Point):    정책을 '결정'하는 곳 (OPA)

흐름:
  PEP → "이 작업 허용?" (input: user, action, resource) → PDP(OPA)
  PDP → rego 정책 평가 → "allow: true/false + 이유" → PEP
  PEP → 결정대로 집행 (허용/거부)

입력(input)과 데이터(data):
  input: 그때그때의 질의 (누가 무엇을)
  data:  정책이 참조하는 배경 데이터 (역할 매핑, 허용 목록...)
  → OPA는 input + data + rego로 결정
```

이 분리의 이점(guide): 정책이 코드에서 빠져 언어 무관·중앙 관리·감사 가능. 하나의 PDP가 여러 PEP를 덮습니다.

## 2. rego — 선언적 정책 언어

```rego
package kubernetes.admission

# 규칙 = "이것이 참이 되는 조건"
deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]   # _ = 모든 요소 순회
    not container.securityContext.runAsNonRoot
    msg := sprintf("container %v must run as non-root", [container.name])
}
```

```
rego 사고법 (guide의 전환):
  - 규칙(deny)은 "본문(조건)이 전부 참일 때" 성립
  - 여러 값에 대해: [_](모든 요소), some x(변수 바인딩)
  - not: 부정 (조건이 거짓일 때)
  - 규칙이 여러 번 성립하면 결과가 집합(set)에 모입니다

핵심 문법:
  package: 네임스페이스
  deny[msg] { ... }: msg를 만족하는 조건 (부분 규칙 — 여러 위반 수집)
  allow { ... }: 불리언 (하나라도 성립하면 참 — 기본 deny + allow 패턴)
  변수 := 값: 대입
  == 비교, = 통합(unification)
  input.a.b[_].c: 경로 순회
```

### 명령형 vs 선언적

```
명령형(Python):
  violations = []
  for c in containers:
      if not c.get('securityContext',{}).get('runAsNonRoot'):
          violations.append(f"{c['name']} must be non-root")

rego(선언적):
  deny[msg] {
      container := input...containers[_]
      not container.securityContext.runAsNonRoot
      msg := ...
  }
→ "순회하며 찾아라"가 아니라 "위반은 이 조건일 때 존재한다"
  OPA가 모든 컨테이너에 대해 규칙을 평가해 집합을 만듭니다
```

## 3. 테스트 — 정책도 코드입니다 (cicd 24)

```rego
# policy_test.rego
test_deny_root_container {
    deny[_] with input as {
        "request": {"kind": {"kind": "Pod"},
                    "object": {"spec": {"containers": [{"name": "app"}]}}}
    }
}
```

```bash
opa test .              # rego 단위 테스트 실행
opa eval -d policy.rego -i input.json "data.kubernetes.admission.deny"
conftest test manifest.yaml -p policy/   # cicd 24의 그것
```

정책의 부정 테스트("무엇이 거부되는가")가 21·24의 규율 — 정책도 테스트 없이 배포하지 않습니다.

## 4. Gatekeeper — K8s admission의 OPA

```
Gatekeeper = OPA + K8s admission 통합 패키징
  ConstraintTemplate: rego 정책 + 파라미터 스키마 (재사용 템플릿)
  Constraint:         템플릿의 인스턴스 (구체적 적용 — 어느 리소스에, 어떤 파라미터)
```

```yaml
# ConstraintTemplate: rego를 담은 재사용 템플릿
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata: { name: k8srequiredlabels }
spec:
  crd:
    spec:
      names: { kind: K8sRequiredLabels }
      validation: { openAPIV3Schema: { properties: { labels: { type: array } } } }
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredlabels
        violation[{"msg": msg}] {
          required := input.parameters.labels[_]
          not input.review.object.metadata.labels[required]
          msg := sprintf("missing label: %v", [required])
        }
---
# Constraint: 템플릿을 구체적으로 적용
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata: { name: require-team-label }
spec:
  match: { kinds: [{ apiGroups: [""], kinds: ["Namespace"] }] }
  parameters: { labels: ["team"] }
```

```
Gatekeeper 특징:
  audit: 기존 리소스의 위반을 주기 검사 (07의 audit→enforce)
  enforcementAction: deny(차단) / dryrun(기록만) / warn
  mutation: 값 주입·수정 (Kyverno보다 나중에 추가된 영역)
  ★ 07·21의 admission 도입 순서(audit→enforce)가 여기서
```

## 5. 다영역 — 하나의 엔진

```
같은 rego 정책이 여러 곳에서:
  ① K8s admission (Gatekeeper) — 배포 시점
  ② CI (conftest) — 파이프라인에서 매니페스트·IaC 검사 (cicd 24)
  ③ 앱 인가 (OPA 서버/라이브러리) — API 요청마다 "허용?"
  ④ Terraform plan 검사 (conftest) — 인프라 변경 규정
  ⑤ Envoy ext_authz (23) — 프록시 레벨 인가
  ⑥ Kafka·SQL·CI/CD 시스템의 인가

★ 07의 "관통하는 정책 엔진":
  조직이 rego 하나로 전 영역 정책을 통일
  "prod에는 서명된 이미지만"을 admission·CI·런타임에서 같은 정책으로
  → 정책의 단일 진실 소스(SSOT)
```

## 6. OPA vs Kyverno — 선택 (32의 예고)

| | OPA/Gatekeeper | Kyverno(32) |
|---|---|---|
| 언어 | rego (전용, 학습 곡선) | YAML/CRD (K8s 친숙) |
| 범위 | 범용 (K8s·CI·앱·Terraform) | K8s 전용 |
| 강점 | 한 언어로 전 영역, 복잡 로직 | 진입 쉬움, K8s 리소스 생성·변형 |
| 약점 | rego 학습, K8s 편의 기능 적음 | K8s 밖 못 씀 |
| 자리 | 다영역 정책 통일 | K8s 정책만, rego 부담 회피 |

```
선택 (cicd 24 완성):
  조직 전체 정책을 한 언어로 통일 목표 → OPA
  K8s 정책만 필요 + 팀이 rego 부담 → Kyverno
  둘을 함께: CI·다영역은 OPA(conftest), K8s admission은 Kyverno도 흔합니다
```

## 7. 소스/도구에서 확인하기

- OPA: https://www.openpolicyagent.org/docs — rego, philosophy
- rego playground: https://play.openpolicyagent.org
- Gatekeeper: https://open-policy-agent.github.io/gatekeeper/
- conftest: https://www.conftest.dev (cicd 24)
- 07·21·24·32 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| OPA의 핵심? | 정책 결정을 앱에서 분리 (PDP) — "할 수 있나요?"를 rego로 답 |
| rego 사고법? | 선언적 — "위반은 이 조건일 때 존재한다"(명령형 순회 아님) |
| input vs data? | 그때그때 질의 vs 배경 데이터(역할·허용목록) |
| Gatekeeper? | OPA + K8s admission — ConstraintTemplate(rego) + Constraint(적용) |
| audit→enforce? | Gatekeeper의 enforcementAction: dryrun→deny (07·21) |
| 다영역? | 같은 rego가 admission·CI·앱 인가·Terraform·Envoy에 |
| OPA vs Kyverno? | 범용 rego(전 영역) vs K8s 네이티브 YAML(진입 쉬움) |
