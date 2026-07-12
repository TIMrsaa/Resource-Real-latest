# 학습 가이드 — 정책이 K8s 리소스가 될 때

## 31의 정반대 선택

31에서 OPA를 배웠습니다: rego라는 전용 언어로 범용성(K8s·CI·앱·Terraform 전 영역)을 얻었습니다. 그 대가는 rego 학습 곡선이었습니다. Kyverno는 정확히 반대를 택합니다:

```
OPA:     rego (새 언어) → 범용성. 대가: 학습 곡선
Kyverno: K8s YAML (익숙) → K8s 전용. 대가: K8s 밖 못 씀
```

Kyverno의 정책은 그냥 K8s 리소스(ClusterPolicy CRD)입니다. K8s를 아는 사람이라면 `kubectl apply`로 정책을 배포하고, `kubectl get policies`로 조회하고, GitOps(14)로 관리합니다 — 새로운 개념이 거의 없습니다. 이것이 "진입 쉬움"의 실체이고, 31의 사고 사례에서 rego 병목을 Kyverno로 푼 이유입니다.

## validate를 넘어서 — 네 가지 능력

정책 엔진을 "검사(validate)"로만 생각하면 Kyverno의 절반만 봅니다. Kyverno는 네 가지를 합니다:

```
validate:     검사 — "이 Pod가 규칙을 지키나요?" (거부/허용) — OPA와 겹침
mutate:       변형 — "모든 Pod에 이 라벨/사이드카를 주입" (admission에서 수정)
generate:     생성 — "새 네임스페이스가 생기면 기본 NetworkPolicy를 만들어라"
verifyImages: 서명 검증 — "이 이미지가 cosign 서명됐나요?" (cicd 21)
```

generate가 특히 독특합니다 — 정책이 리소스를 **만듭니다**. "모든 네임스페이스에 default-deny NetworkPolicy가 있어야 한다"를 검사(validate)로 하면 위반을 알려줄 뿐이지만, generate로 하면 없으면 자동으로 만듭니다. 이것은 OPA/Gatekeeper가 나중에 추가한 영역이고, Kyverno의 강점입니다.

## 정책이 K8s 리소스라는 것의 의미

```
정책이 CRD → GitOps로 관리(14), kubectl로 조회, RBAC로 접근 제어
정책 위반 = PolicyReport CRD → kubectl get policyreport로 감사 (07의 audit)
mutate/generate = admission·백그라운드에서 실제 리소스 조작
```

31의 OPA가 "외부 결정 엔진"이라면 Kyverno는 "K8s 안에 녹아든 정책 컨트롤러"다 — K8s의 선언적 모델(08의 오퍼레이터 패턴)이 정책에 적용된 것입니다.

## 이 모듈이 완성하는 것

31과 32를 함께 배우면 cicd 24에서 예고한 "OPA vs Kyverno"의 선택이 완성됩니다. 그리고 31의 사고 사례가 도달한 결론 — "함께 쓴다"(다영역·복잡 로직은 OPA, 팀별 K8s 정책은 Kyverno) — 을 여기서 구체적 분담으로 정리합니다. 선택은 "어느 것이 낫나"가 아니라 "어느 영역을 어느 도구로"다.
