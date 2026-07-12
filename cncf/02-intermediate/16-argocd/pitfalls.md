# 흔한 함정 5선

## 1. controller가 클러스터의 모든 리소스를 watch한다는 사실을 모름

ArgoCD의 application-controller 메모리는 관리하는 **앱 수**가 아니라 대상 클러스터의 **리소스 총량**이 지배합니다 — 모든 종류를 watch해 캐시하기 때문입니다. Cilium(CiliumEndpoint가 Pod마다), Event, EndpointSlice 같은 것이 수만 개 있으면 controller가 OOM으로 죽습니다. 방어는 `argocd-cm`의 `resource.exclusions`로 watch 범위를 좁히는 것 — 이것은 controller 메모리와 **대상 클러스터 API 서버 부하**를 동시에 줄입니다. "왜 대상 클러스터 API가 바쁜가"의 답이 ArgoCD인 경우가 흔한데, 아무도 그것을 의심하지 않습니다.

## 2. webhook 없이 폴링에만 의존

기본 reconcile 주기는 3분입니다 — 배포가 최대 3분 늦고, 앱이 수백 개면 그 주기를 지키느라 controller가 계속 바쁩니다. GitHub/GitLab webhook을 붙이면 커밋 즉시 refresh되고 폴링 부담이 줄어듭니다(주기를 늘릴 수 있습니다). "GitOps는 느리다"는 오해의 절반이 webhook 미설정이고, 나머지 절반은 repo-server 렌더링 대기입니다. 규모 운영의 첫 두 손잡이가 이것입니다.

## 3. ApplicationSet의 삭제 위험을 방치

생성기 파라미터(클러스터 라벨, Git 디렉터리 존재 여부, PR 상태)가 바뀌면 Application이 사라지고 — 기본 설정에서는 **그 워크로드도 함께 삭제됩니다**(lab-02 Step 2에서 실증). 누군가 클러스터 Secret의 라벨을 고치거나 GitOps 저장소의 디렉터리를 리팩터링하는 순간 프로덕션이 지워질 수 있습니다. 프로덕션 ApplicationSet에는 `syncPolicy.applicationsSync: create-update`(삭제 금지)와 `preserveResourcesOnDeletion: true`(앱이 지워져도 워크로드 유지)를 걸고, 변경은 PR 리뷰 + dry-run으로. 편의의 대가는 늘 폭발 반경입니다.

## 4. 대상 클러스터에 cluster-admin 토큰을 주고 잊음

멀티클러스터 등록은 대상 클러스터의 SA 토큰을 허브의 Secret에 저장하는 일입니다 — 대개 튜토리얼대로 cluster-admin을 줍니다. 그 순간 **ArgoCD 침해 = 등록된 모든 클러스터의 완전 장악**이 됩니다(07의 신뢰 경계, cicd 22의 시크릿 집중 리스크). 방어: 대상 SA 권한을 실제 배포에 필요한 것으로 축소, ArgoCD 네임스페이스의 접근 통제(RBAC·NetworkPolicy), 토큰 순환 절차, 그리고 폭발 반경이 중요하면 클러스터별 ArgoCD(형태 C)를 검토. "중앙집중의 편의"에는 이 대가가 붙어 있고, 대가를 문서에 적지 않으면 아무도 모릅니다.

## 5. AppProject 없이 RBAC만, 또는 그 반대

RBAC는 "누가 무엇을 할 수 있는가"(sync·delete)를 통제하지만, 앱이 **어디에 무엇을 배포하는가**는 막지 못합니다 — dev 팀의 앱이 kube-system에 DaemonSet을 심을 수 있습니다. AppProject는 소스 저장소·목적지 네임스페이스·리소스 종류를 화이트리스트로 좁히지만, "prod 앱을 누가 sync하는가"는 정하지 못합니다. **두 층이 함께여야 경계가 섭니다**: AppProject(무엇을 어디에) + RBAC(누가 무엇을). cicd 24에서 배운 "강제는 좁게, 명확하게"의 배달 층 구현이며, 하나만 세우면 반쪽 통제로 안심하게 됩니다.

## 실무 사고 사례

> 한 조직이 GitOps 저장소를 리팩터링했습니다 — `apps/` 아래 평평하던 디렉터리들을 `apps/<team>/<service>/`로 계층화하는, 순수하게 정리 목적의 PR이었습니다. 리뷰어 둘이 승인했고 머지됐습니다. 3분 뒤, ApplicationSet의 git 디렉터리 생성기(`directories: [{path: "apps/*"}]`)가 새 구조를 스캔했고 — 기존 경로에 매칭되던 Application 47개가 **사라졌습니다**. `preserveResourcesOnDeletion`이 설정되어 있지 않았으므로 ArgoCD는 각 앱의 리소스를 정직하게 정리했습니다: 47개 서비스의 Deployment·Service·Ingress가 프로덕션에서 삭제됐습니다. 복구는 Git revert 후 재sync로 11분, 그러나 그중 세 서비스는 PVC가 함께 삭제되어(cascade) 데이터 복원에 4시간이 걸렸습니다. 포스트모템의 핵심 질문은 "왜 아무도 몰랐나"였고, 답이 뼈아팠습니다: ① ApplicationSet의 변경이 **디렉터리 이름 변경만으로** 트리거된다는 것을 PR 리뷰어가 인지하지 못했습니다(PR에는 YAML 한 줄도 안 바뀌었습니다 — 파일이 이동했을 뿐). ② `applicationsSync`와 `preserveResourcesOnDeletion` 옵션의 존재를 팀이 몰랐습니다. ③ ApplicationSet의 변경을 미리 보는 절차(dry-run·diff)가 없었습니다. 개선: 프로덕션 ApplicationSet 전부에 두 방어 옵션 적용, `argocd appset generate`(dry-run)를 PR 게이트로, 그리고 GitOps 저장소의 디렉터리 구조 변경을 "고위험 변경" 목록에 등재해 별도 승인(cicd 24)을 요구. 교훈: **ApplicationSet은 앱을 만드는 앱이고, 앱을 지우는 앱이기도 합니다** — 생성기의 입력이 무엇인지, 그리고 그 입력을 누가 무심코 바꿀 수 있는지를 아는 것이 이 기능의 사용 조건입니다.
