# 이론 — 아키텍처, 네 규칙 타입, 정책=리소스, OPA 대비, 선택

> **🌱 17세 눈높이 비유: 학교의 자동 행정 시스템**
> - **31(OPA)** = 외부 규정 심판 — 교실이 "이거 되나요?"를 물으면 규정집(rego)으로 답합니다
> - **Kyverno** = 학교 행정 시스템에 내장된 규정 — 별도 언어 없이 학교 서식(K8s YAML)으로 규정을 씁니다
>   - **validate** = 서류 검사 ("이 신청서가 규정에 맞나요?")
>   - **mutate** = 서류 자동 보완 ("모든 신청서에 학번 도장을 찍어라")
>   - **generate** = 자동 발급 ("새 학생이 등록되면 사물함을 자동 배정")
>   - **verifyImages** = 위조 방지 확인 ("이 증명서에 진품 홀로그램이 있나요?")
> - **정책이 서식이라는 것** = 규정을 다른 서류처럼 보관·조회·버전관리 (GitOps)

---

## 1. 아키텍처

```
Kyverno:
  admission webhook (validating + mutating)
    → API 요청 시점에 validate/mutate/verifyImages 적용
  백그라운드 컨트롤러
    → generate(리소스 생성), 기존 리소스 재평가(정책 변경 시)
    → PolicyReport 생성 (위반 감사 — 07의 audit)

정책은 CRD:
  ClusterPolicy (클러스터 스코프) / Policy (네임스페이스 스코프)
  PolicyReport / ClusterPolicyReport (위반 결과)
  → kubectl get clusterpolicy / policyreport 로 관리·감사
```

## 2. 네 규칙 타입

### validate — 검사 (OPA와 겹침)

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: require-non-root }
spec:
  rules:
    - name: check-non-root
      match: { any: [{ resources: { kinds: [Pod] } }] }
      validate:
        failureAction: Audit            # ★ Audit → Enforce (07의 순서) — 규칙 단위 (구 spec.validationFailureAction은 폐기 예정)
        message: "containers must run as non-root"
        pattern:                         # ★ 패턴 매칭 (YAML로 규칙)
          spec:
            containers:
              - securityContext:
                  runAsNonRoot: true
```

```
검사 방법 셋:
  pattern:  YAML 패턴 매칭 (=(선택), *(와일드카드), !(부정), >(연산))
  deny:     조건식 (JMESPath/CEL)
  cel:      CEL 표현식 (K8s의 표준 표현식 언어 — VAP와 같은)
★ rego 없이 K8s YAML로 (31의 대가였던 학습 곡선 회피)
```

### mutate — 변형

```yaml
    - name: add-default-labels
      match: { any: [{ resources: { kinds: [Pod] } }] }
      mutate:
        patchStrategicMerge:             # 또는 patchesJson6902
          metadata:
            labels:
              team: "{{ request.namespace }}"   # 변수 치환
          spec:
            securityContext:
              runAsNonRoot: true          # 값을 주입(강제가 아니라 수정)
```

```
용도: 기본값 주입(라벨·securityContext), 사이드카 주입, 이미지 다이제스트 고정
★ validate는 거부, mutate는 고쳐서 통과 (다른 접근)
  "non-root가 아니면 거부" vs "non-root로 만들어서 통과"
```

### generate — 정책이 리소스를 만듭니다 (Kyverno의 독특함)

```yaml
    - name: default-networkpolicy
      match: { any: [{ resources: { kinds: [Namespace] } }] }
      generate:
        apiVersion: networking.k8s.io/v1
        kind: NetworkPolicy
        name: default-deny
        namespace: "{{ request.object.metadata.name }}"
        synchronize: true                # 원본 삭제/변경 시 동기화
        data:
          spec:
            podSelector: {}
            policyTypes: [Ingress, Egress]   # 기본 차단 (04)
```

```
효과: 새 네임스페이스 생성 → 자동으로 default-deny NetworkPolicy 생성
  validate라면: "NetworkPolicy가 없다"고 경고만
  generate라면: 없으면 만듭니다 (선언 → 실현)
★ OPA/Gatekeeper가 나중에 추가한 영역, Kyverno의 강점
  "모든 네임스페이스에 X가 있어야 한다"를 강제가 아니라 생성으로
```

### verifyImages — 서명 검증 (cicd 21)

```yaml
    - name: verify-signature
      match: { any: [{ resources: { kinds: [Pod] } }] }
      verifyImages:
        - imageReferences: ["ghcr.io/myorg/*"]
          attestors:
            - entries:
                - keyless:               # cosign keyless (cicd 21)
                    subject: "https://github.com/myorg/*/.github/workflows/*"
                    issuer: "https://token.actions.githubusercontent.com"
```

```
→ cicd 21에서 배운 admission 서명 검증이 Kyverno의 규칙 타입
  keyless(OIDC 신원) 또는 key 기반 (21의 sigstore)
```

## 3. 정책이 K8s 리소스 — 선언적 관리

```
정책 배포: kubectl apply -f policy.yaml (GitOps로 — 14)
정책 조회: kubectl get clusterpolicy
위반 감사: kubectl get policyreport -A (07의 audit)
접근 제어: RBAC로 누가 정책을 만들 수 있나 (24의 거버넌스)

★ 08의 오퍼레이터 패턴이 정책에:
  CRD(정책) + 컨트롤러(Kyverno) = 정책의 코드화·선언화
  31의 OPA(외부 결정 엔진)와 대비: Kyverno는 K8s에 녹아든 컨트롤러
```

## 4. OPA vs Kyverno — 최종 비교 (cicd 24 완성)

| | OPA/Gatekeeper(31) | Kyverno(32) |
|---|---|---|
| 언어 | rego (전용, 학습) | YAML/CEL (K8s 친숙) |
| 범위 | 범용(K8s·CI·앱·TF·Envoy) | K8s 전용 |
| validate | ✅ | ✅ |
| mutate | 나중에 추가 | ✅ 강함 |
| generate | (제한적) | ✅ **독특한 강점** |
| verifyImages | 별도 구성 | ✅ 내장(21) |
| 복잡 로직 | rego의 표현력 | 패턴·CEL(제한적) |
| 진입 | 어려움(rego) | 쉬움(YAML) |
| 다영역 | ✅ | ❌ |

## 5. 선택과 함께 쓰기 (31의 결론 구체화)

```
Kyverno를 고르는 경우:
  - K8s 정책만 필요 (CI·앱 인가·Terraform 불필요)
  - 팀이 rego를 부담스러워함 (서비스 팀이 직접 정책 작성)
  - mutate/generate가 필요 (기본값 주입, 리소스 자동 생성)
  - verifyImages(서명 검증)를 K8s에 통합 (21)

OPA를 고르는 경우(31):
  - 조직 전체 정책 통일(admission+CI+앱+Terraform)
  - 복잡한 정책 로직 (rego의 표현력)

함께 쓰기 (31 사고 사례의 결론):
  K8s admission의 단순·팀별 정책 → Kyverno (서비스 팀이 YAML로)
  CI·다영역·복잡 로직 → OPA (플랫폼 팀이 rego로)
  → 각 도구를 강점에 배치, rego 병목 회피

★ K8s에 CEL 기반 ValidatingAdmissionPolicy(VAP)가 코어로 들어오며
  "검사"의 상당 부분은 코어 기능으로 이동 중 (k8s 34)
  Kyverno·OPA는 그 위의 고급 기능(mutate·generate·복잡 로직·다영역)으로 차별화
```

## 6. 소스/도구에서 확인하기

- Kyverno: https://kyverno.io/docs — validate/mutate/generate/verifyImages
- 정책 라이브러리: https://kyverno.io/policies/ (검증된 정책 모음)
- CEL: K8s ValidatingAdmissionPolicy와 공유
- 31(OPA)·21(서명)·07(시간선)·k8s 34(VAP) 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| Kyverno의 선택? | 정책을 K8s YAML로 — rego 없이(31의 대가 회피), K8s 전용 |
| 네 규칙 타입? | validate(검사)/mutate(변형)/generate(생성)/verifyImages(서명) |
| generate의 독특함? | 정책이 리소스를 만듭니다 (없으면 자동 생성 — OPA의 약점 영역) |
| mutate? | 거부가 아니라 고쳐서 통과 (기본값 주입·사이드카) |
| 정책=리소스? | CRD → GitOps·kubectl·RBAC로 관리, PolicyReport 감사 |
| verifyImages? | cosign 서명 검증 내장 (cicd 21) |
| OPA vs Kyverno? | 범용 rego vs K8s 네이티브 — 함께 쓰기가 현실적 결론 |
| VAP의 영향? | 검사는 K8s 코어(CEL)로 이동, 엔진은 고급 기능으로 차별화 |
