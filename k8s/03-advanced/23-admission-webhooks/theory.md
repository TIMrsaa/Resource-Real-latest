# 이론 — 웹훅 규약, CEL 정책, failurePolicy 설계

> **🌱 17세 눈높이 비유: 공항 보안검색대의 두 가지 검사**
> - **CEL 정책** = 검색대의 **자동 스캐너**. 규칙(액체 100ml 초과 금지)이 기계에 내장되어 즉석 판정 — 빠르고 고장 나도 스캐너만 바꾸면 됩니다.
> - **웹훅** = "본부에 전화해서 물어보는" 검사. 뭐든 물어볼 수 있지만(블랙리스트 조회), **본부 전화가 불통이면?** 규정상 두 선택지뿐입니다: 전원 통과(Ignore — 보안 구멍) 또는 전원 억류(Fail — 공항 마비).
> - **Mutating** = 검사 중에 "이건 이렇게 포장 바꿔드릴게요"까지 하는 것 (사이드카 주입).

---

## 1. 웹훅 호출 규약

등록(설정 리소스):

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration        # 또는 MutatingWebhookConfiguration
webhooks:
- name: policy.example.com
  clientConfig:
    service: { name: my-webhook, namespace: policy, path: /validate, port: 443 }
    caBundle: <base64 CA>                   # API서버가 웹훅 서버를 신뢰할 근거 (TLS 필수!)
  rules:
  - {apiGroups: ["apps"], apiVersions: ["v1"], operations: ["CREATE","UPDATE"], resources: ["deployments"]}
  failurePolicy: Fail                       # Fail(거부) / Ignore(통과)
  timeoutSeconds: 5                         # 1~30 (기본 10) — 짧게!
  sideEffects: None
  namespaceSelector:                        # 폭발 반경 제한의 핵심
    matchExpressions:
    - { key: kubernetes.io/metadata.name, operator: NotIn, values: [kube-system, policy] }
```

호출: API 서버 → POST `AdmissionReview(JSON)` → 웹훅 응답:

```json
// Validating 응답
{"apiVersion":"admission.k8s.io/v1","kind":"AdmissionReview",
 "response":{"uid":"<요청 uid>","allowed":false,"status":{"message":"latest 태그 금지"}}}
// Mutating 응답: allowed + JSONPatch(base64)
{"response":{"uid":"...","allowed":true,"patchType":"JSONPatch",
 "patch":"W3sib3AiOiJhZGQiLCJwYXRoIjoi...In1d"}}   // [{"op":"add","path":...}]
```

순서 보장: 모든 Mutating(순서 비결정) → 검증 → 모든 Validating(병렬). **Mutating 웹훅끼리는 서로의 결과를 본다는 보장이 없습니다** — 변형 충돌 주의.

## 2. ValidatingAdmissionPolicy — CEL로 인프로세스 검증

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata: { name: no-latest-tag }
spec:
  matchConstraints:
    resourceRules:
    - {apiGroups: ["apps"], apiVersions: ["v1"], operations: ["CREATE","UPDATE"], resources: ["deployments"]}
  validations:
  - expression: "object.spec.template.spec.containers.all(c, !c.image.endsWith(':latest') && c.image.contains(':'))"
    message: "이미지는 명시적 태그 필수, :latest 금지"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding      # 정책을 "어디에" 적용할지 분리 (Gateway/Route 같은 역할 분리!)
metadata: { name: no-latest-tag-binding }
spec:
  policyName: no-latest-tag
  validationActions: [Deny]                 # Deny / Warn / Audit — 점진 도입의 열쇠!
  matchResources:
    namespaceSelector:
      matchExpressions:
      - { key: environment, operator: In, values: [prod] }
```

### CEL 미니 문법 (검증에서 쓰는 것만)

```
object / oldObject               # 새/기존 객체
object.metadata.?labels.team     # ?: 없을 수 있는 필드 (optional)
has(object.spec.replicas)        # 필드 존재 확인
containers.all(c, 조건) / exists(c, 조건)
"prod" in object.metadata.labels # 키 존재
variables.xxx                    # spec.variables로 정의한 재사용 식
params.maxReplicas               # 바인딩이 주입하는 파라미터 (정책의 일반화!)
```

### 점진 도입 3단계 (운영 표준)

```
validationActions: [Audit]   → 감사 로그에만 기록 (현황 파악)
                 → [Warn]    → kubectl에 경고 표시 (개발자 교육 기간)
                 → [Deny]    → 강제
```

## 3. failurePolicy 설계 — 가용성 vs 보안의 저울

| 정책 | 웹훅 다운 시 | 적합 |
|------|--------------|------|
| Fail | 대상 요청 전부 **거부** | 보안 필수 정책 (우회되면 안 됨) |
| Ignore | 검사 없이 **통과** | 편의 기능 (라벨 주입 등) |

Fail을 쓸 때의 의무사항 (이 중 하나라도 빠지면 시한폭탄):
1. **웹훅 서버의 HA** (replicas 2+, PDB, 멀티 AZ — 모듈 12/19의 기술들)
2. **namespaceSelector로 kube-system과 웹훅 자신의 ns 제외** — 안 그러면 "웹훅이 죽으면 웹훅을 재시작할 Pod도 못 만드는" 데드락
3. timeoutSeconds 최소화 (5초 이하) — 느린 웹훅은 모든 kubectl을 느리게 만듭니다
4. rules를 최소 범위로 (모든 리소스 `*`를 보는 웹훅 금지)

## 4. 생태계 지도

| 도구 | 정체 |
|------|------|
| **Kyverno** | YAML로 정책 작성 → 웹훅+CEL로 집행 (K8s 네이티브, cncf 파트 32) |
| **OPA Gatekeeper** | Rego 언어 정책 → 웹훅 집행 (cncf 파트 31) |
| Pod Security Admission | K8s 내장 Pod 보안 검사 (모듈 32) — 웹훅 아닌 내장 admission |
| 직접 웹훅 | 위 도구로 안 되는 커스텀 (Operator의 일부로 — 모듈 30) |

## 5. 소스코드에서 확인하기

- 웹훅 호출부: `staging/src/k8s.io/apiserver/pkg/admission/plugin/webhook/validating/dispatcher.go` — failurePolicy 분기가 그대로 보입니다
- CEL 평가기: `staging/src/k8s.io/apiserver/pkg/admission/plugin/policy/validating/` 
- CEL 라이브러리(K8s 확장): `staging/src/k8s.io/apiserver/pkg/cel/library/`

## 요약 카드

| 질문 | 답 |
|------|----|
| CEL vs 웹훅 선택? | CEL 우선 — 외부 조회/변형 필요할 때만 웹훅 |
| 웹훅 TLS가 필수인 이유? | API 서버가 caBundle로 검증 — 관문 위조 방지 |
| Mutating끼리 순서? | 보장 없음 — 서로 의존하는 변형 금지 |
| Fail 정책의 3대 의무? | 웹훅 HA + kube-system/자기 ns 제외 + 짧은 timeout |
| 점진 도입 경로? | Audit → Warn → Deny |
