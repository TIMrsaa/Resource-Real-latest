# Lab 02 — OPA vs Kyverno: 같은 정책, 두 도구, 그리고 최종 선택

31과 32를 나란히 놓아 cicd 24에서 예고한 선택을 완성합니다.

전제: lab-01의 클러스터(kind: kyverno), 31의 rego 지식.

## Step 1. 같은 정책을 두 도구로 — non-root 강제

```bash
cat <<'EOF'
=== "컨테이너는 non-root여야 한다" — 두 표현 ===

[OPA/Gatekeeper — rego (31)]
  ConstraintTemplate:
    rego: |
      package x
      violation[{"msg": msg}] {
        c := input.review.object.spec.containers[_]
        not c.securityContext.runAsNonRoot
        msg := sprintf("%v must be non-root", [c.name])
      }
  + Constraint (적용)

[Kyverno — YAML (32)]
  ClusterPolicy:
    validate:
      pattern:
        spec:
          containers:
            - securityContext:
                runAsNonRoot: true

→ 같은 정책, 다른 표현:
  OPA: rego 로직 (표현력, 학습 곡선)
  Kyverno: YAML 패턴 (익숙, 제한적 표현력)
EOF
```

## Step 2. Kyverno가 쉬운 영역 — 단순 정책

```bash
# 서비스 팀이 직접 쓸 법한 단순 정책 — Kyverno가 진입 쉬움
kubectl apply -f - <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: require-resources }
spec:
  rules:
    - name: require-limits
      match: { any: [{ resources: { kinds: [Pod] } }] }
      validate:
        failureAction: Audit
        message: "resource limits required"
        pattern:
          spec:
            containers:
              - resources:
                  limits:
                    memory: "?*"    # 아무 값이나 있어야 (와일드카드)
                    cpu: "?*"
EOF
sleep 5
echo "→ 이런 단순 정책은 서비스 팀이 K8s YAML로 직접 (rego 몰라도)"
echo "  31 사고 사례에서 rego 병목을 Kyverno로 푼 지점"
```

## Step 3. OPA가 강한 영역 — 복잡 로직·다영역

```bash
cat <<'EOF'
=== OPA가 강한 곳 (31) ===
① 복잡한 로직:
   "이미지가 (A이고 B) 또는 (C이고 D가 아님)" 같은 복잡한 조건
   여러 리소스를 교차 참조하는 정책
   → rego의 표현력 (Kyverno 패턴/CEL은 제한적)

② 다영역:
   같은 정책을 K8s admission + CI(conftest) + Terraform + 앱 인가에
   → OPA는 하나의 rego로 (Kyverno는 K8s만)

③ 조직 전체 통일:
   "prod에는 서명 이미지만"을 admission·CI·런타임에서 같은 소스로
   → 07의 관통 엔진 (OPA)

Kyverno가 강한 곳:
① generate: 정책이 리소스를 만듭니다 (lab-01 — OPA 약점)
② mutate: 기본값·사이드카 주입 (강력)
③ verifyImages: 서명 검증 내장 (21)
④ 진입 쉬움: 서비스 팀이 직접 YAML로
EOF
```

## Step 4. 함께 쓰기 — 실제 조직의 분담 (31 사고 사례의 결론)

```bash
cat <<'EOF'
=== 함께 쓰는 전형 (cicd 24 완성) ===

플랫폼 팀 (rego 능력):
  OPA/conftest → CI에서 매니페스트·IaC·워크플로 검사 (cicd 24)
  OPA → Terraform plan 검사, 앱 인가, 다영역 통일
  복잡한 조직 정책 (rego의 표현력)

서비스 팀 (K8s만 앎):
  Kyverno → 팀별 K8s admission 정책 (라벨·리소스·태그)
  Kyverno generate → 네임스페이스 기본 리소스(NetworkPolicy·Quota)
  Kyverno mutate → 사이드카·기본값
  Kyverno verifyImages → 서명 검증(21)

→ 각 도구를 강점에 배치, rego 병목 회피
  "어느 것이 낫나"가 아니라 "어느 영역을 어느 도구로"
EOF
```

## Step 5. K8s 코어의 VAP — 정책의 미래 (k8s 34)

```bash
cat <<'EOF'
=== ValidatingAdmissionPolicy (VAP) — 코어로 들어온 정책 ===
K8s 1.30+ 코어 기능: CEL 기반 admission 정책 (외부 엔진 불필요!)

apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
spec:
  validations:
    - expression: "object.spec.containers.all(c, c.securityContext.runAsNonRoot == true)"
                                          ↑ CEL 표현식

의미:
  단순 "검사(validate)"는 K8s 코어(CEL)로 이동 중
  → OPA/Kyverno 없이도 기본 검사 가능

그럼 OPA/Kyverno는?
  Kyverno: mutate·generate·verifyImages·정책 라이브러리 (검사 이상)
  OPA: 다영역(CI·앱·TF)·복잡 로직 (K8s 밖)
  → "검사"는 코어로, 엔진은 고급 기능으로 차별화 (theory §5)

★ 정책 도구 선택 시: "단순 검사면 VAP로 충분한가?"를 먼저
  (34에서 VAP를 사용자로 배웠다면, 여기서 정책 도구와의 관계)
EOF
kubectl api-resources | grep -i validatingadmissionpolicy | head -2 || \
  echo "(K8s 1.30+ 에서 VAP 사용 가능)"
```

## Step 6. 선택 결정 트리 — 종합

```bash
cat <<'EOF'
=== 정책 도구 선택 (31+32 종합) ===

Q1. 단순 검사(라벨·필드 존재)만 필요한가?
  Yes → K8s 코어 VAP (CEL) — 외부 엔진 불필요 (k8s 34)
  ↓

Q2. K8s 리소스 생성/변형(generate/mutate)이 필요한가?
  Yes → Kyverno (독특한 강점)
  ↓

Q3. 서명 검증(verifyImages)을 admission에?
  Yes → Kyverno 내장 (또는 sigstore policy-controller)
  ↓

Q4. K8s 밖(CI·Terraform·앱 인가) 정책 통일이 필요한가?
  Yes → OPA (다영역, 관통 엔진)
  ↓

Q5. 복잡한 정책 로직인가요?
  Yes → OPA (rego 표현력)
  아니면 → 팀 역량에 따라 (rego 되면 OPA, 아니면 Kyverno)

★ 대부분의 조직: Kyverno(K8s 정책) + OPA(CI·다영역) + VAP(단순 검사)
  세 층이 겹치지 않게 역할 분담
EOF
```

## Step 7. 산출물 — 정책 엔진 종합 카드

```markdown
# 정책 엔진 선택 (07·21·24·31·32·k8s34 종합)
| 필요 | 도구 |
|------|------|
| 단순 검사(필드·라벨) | K8s VAP (CEL 코어) |
| K8s 리소스 생성/변형 | Kyverno (generate/mutate) |
| 서명 검증 admission | Kyverno verifyImages (21) |
| CI·IaC·워크플로 검사 | OPA conftest (24) |
| 다영역·복잡 로직 | OPA rego |
| 팀이 rego 부담 | Kyverno (YAML) |

## 공통 규율 (모든 정책 도구)
- Audit → Enforce 이행 (07·21)
- 정책도 테스트 (24·31)
- webhook failurePolicy 선택 (보안 vs 가용성 — 21)
- 정책=코드=GitOps (14)
```

## 정리

```bash
bash cleanup.sh
```
