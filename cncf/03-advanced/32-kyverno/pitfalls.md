# 흔한 함정 5선

## 1. 처음부터 Enforce로 (07·21·31의 반복)

`failureAction: Enforce`(구 `validationFailureAction`)를 dryrun/Audit 없이 바로 켜면 기존 워크로드의 재시작·스케일아웃이 연쇄 거절되어 클러스터가 마비됩니다 — admission·서명 검증·정책 엔진 어디서나 동일한 함정입니다. Kyverno도 예외가 아닙니다: Audit로 시작해 PolicyReport로 위반 목록을 확보하고(기존 리소스가 몇 개나 위반하는지), 팀별 이행 기간을 준 뒤, 신규 네임스페이스부터 Enforce, 마지막에 전체 Enforce + 예외. `kubectl get policyreport -A`로 audit 결과를 보는 것이 이행의 출발점입니다.

## 2. generate의 synchronize·소유권을 오해

generate로 만든 리소스는 정책이 소유합니다 — `synchronize: true`면 누가 지워도 재생성되고 원본 정책 변경 시 동기화됩니다. 이것을 모르면 "NetworkPolicy를 지웠는데 계속 돌아온다"(정상 — synchronize)나 "정책을 지웠는데 생성된 리소스가 남아있다"(generate 정리 정책 확인 필요)에 혼란스러워합니다. 그리고 generate가 만드는 리소스가 다른 정책·컨트롤러와 충돌할 수 있습니다(예: generate가 만든 NetworkPolicy를 다른 도구가 관리하려 함). generate는 강력하지만 "정책이 리소스의 주인이 된다"는 소유권 함의를 이해하고 써야 합니다.

## 3. mutate가 만든 변경을 validate가 거부하는 순서 문제

mutate와 validate 정책이 함께 있으면 순서가 중요합니다 — Kyverno는 mutate를 먼저 적용하고 그 결과를 validate하지만, 여러 정책의 상호작용에서 예상 못 한 결과가 나올 수 있습니다(mutate가 주입한 값을 다른 validate가 거부하거나, 두 mutate가 같은 필드를 다르게 수정). 그리고 mutate는 admission에서 리소스를 바꾸므로 "내가 apply한 것과 실제 생성된 것이 다르다"(GitOps의 diff 문제 — 15의 Helm 3-way 병합과 유사). 복잡한 mutate/validate 조합은 테스트(Kyverno CLI의 `kyverno test`)로 검증하고, GitOps에서는 mutate 결과를 인지하세요.

## 4. webhook 성능·가용성을 간과

Kyverno의 admission webhook은 모든 매칭 리소스 요청을 가로챕니다 — 정책이 많거나 복잡하면(특히 verifyImages는 외부 레지스트리·Rekor 조회) admission 지연이 생기고 webhookTimeoutSeconds를 넘으면 요청이 실패합니다. 그리고 Kyverno가 죽으면 failurePolicy에 따라 요청이 막히거나(fail-closed) 통과합니다(fail-open) — 21에서 배운 보안 대 가용성 선택입니다. 대응: 정책을 필요한 리소스에만 매칭(match를 좁게), verifyImages의 타임아웃·캐시, Kyverno의 HA 배포, failurePolicy 명시. 정책 엔진이 클러스터의 모든 배포 경로에 있다는 것을 의식하세요.

## 5. "Kyverno vs OPA"를 이분법으로

31의 사고 사례가 도달한 결론을 반복합니다 — 둘은 대칭적 강약점을 가지며 함께 쓰는 것이 현실적입니다. "우리는 Kyverno 진영"이라며 CI 정책까지 Kyverno로 억지로 하거나(K8s 전용이라 안 됨), "OPA로 통일"이라며 서비스 팀에게 rego를 강요하면(병목) 각각 실패합니다. 그리고 K8s 1.30+의 VAP(CEL 기반 코어 admission)가 단순 검사를 흡수하면서 지형이 또 바뀝니다 — 단순 검사는 VAP, K8s 리소스 조작은 Kyverno, 다영역·복잡 로직은 OPA. "어느 것이 낫나"가 아니라 "어느 영역을 어느 도구로, 그리고 VAP로 충분한 것은 무엇인가"가 실제 질문입니다.

## 실무 사고 사례

> 한 회사가 멀티테넌트 K8s 플랫폼을 운영하며 Kyverno의 generate를 적극 활용했습니다 — 새 테넌트 네임스페이스가 생기면 default-deny NetworkPolicy, ResourceQuota, LimitRange, 기본 RBAC를 자동 생성하는 정책들이었습니다. 우아했고 온보딩이 자동화됐습니다. 문제는 GitOps(ArgoCD — 16)와의 상호작용에서 왔습니다. 일부 팀이 자기 네임스페이스의 NetworkPolicy를 GitOps로도 관리하기 시작했는데 — Kyverno의 generate(synchronize: true)가 만든 NetworkPolicy와 ArgoCD가 배포하려는 NetworkPolicy가 **같은 리소스를 두고 싸웠습니다.** Kyverno가 자기 버전으로 되돌리고, ArgoCD가 OutOfSync를 감지해 자기 버전으로 sync하고, Kyverno가 다시 되돌리는 무한 루프였습니다(16에서 배운 "두 진실이 싸운다"의 정책 엔진판). 게다가 mutate 정책이 모든 Pod에 사이드카를 주입했는데, 그 주입 결과가 GitOps 저장소에 없어서 ArgoCD가 계속 diff를 감지했습니다(15의 Helm 3-way 병합 문제와 동형). 개선은 소유권 정리였습니다: ① generate가 만드는 리소스와 GitOps가 관리하는 리소스의 **경계를 명확히** — 테넌트 기본 리소스는 Kyverno(generate)가, 팀별 커스텀은 GitOps가, 겹치지 않게. ② ArgoCD의 ignoreDifferences로 Kyverno mutate가 주입하는 필드를 무시(16의 필드 소유권). ③ 정책과 GitOps의 역할을 문서화 — "누가 이 리소스의 주인인가". 회고 문장이 이 모듈의 요지였습니다: "Kyverno의 generate·mutate는 강력하지만, **정책이 리소스를 만들고 바꾸는 순간 그것은 리소스의 주인이 됩니다** — 그리고 K8s에는 이미 리소스의 주인이 여럿(GitOps·HPA·다른 컨트롤러) 있습니다. 정책 엔진을 도입한다는 것은 소유권 지도에 새 주인을 추가하는 것이고, 그 경계를 그리지 않으면 주인들이 싸웁니다."
