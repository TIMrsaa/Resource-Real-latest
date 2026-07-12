# 자가 점검 퀴즈

**Q1.** ArgoCD 컴포넌트별 병목과 확장 수단을 표로 정리하세요. "감춰진 부하"는 무엇인가요?

**Q2.** application-controller의 메모리를 지배하는 것은 무엇인가요? 방어 수단은?

**Q3.** "sync가 느리다"와 "OutOfSync 감지가 늦다"는 각각 어느 컴포넌트의 문제인가요?

**Q4.** 멀티클러스터 3형태와 각각의 트레이드오프는? 중앙집중의 숨은 대가는?

**Q5.** ApplicationSet 생성기 다섯 가지를 들고, 생성기의 구조적 위험과 두 방어 옵션을 말하세요.

**Q6.** app-of-apps와 ApplicationSet의 차이와, 함께 쓰는 방식은?

**Q7.** AppProject와 RBAC가 각각 통제하는 것과, 왜 둘 다 필요한가?

**Q8.** 사고 사례에서 "YAML 한 줄도 안 바뀐 PR"이 47개 서비스를 지운 메커니즘을 설명하세요.

---

## 정답

**A1.** repo-server: Git fetch + 렌더링(helm template/kustomize build) → CPU·디스크·동시성 병목, replicas↑·`--parallelismlimit`·캐시로 대응. application-controller: 클러스터 watch·diff·sync → 메모리(리소스 캐시)와 리스트 부하, 샤딩·resource.exclusions로 대응. redis: 렌더·상태 캐시 → 죽으면 전 앱 재렌더(HA 필요). server: 사용자 부하(대개 문제 아님). **감춰진 부하**: 대상 클러스터의 API 서버 — ArgoCD가 그 클러스터의 리소스를 watch하느라 대상 API를 계속 바쁘게 합니다.

**A2.** 관리하는 앱 수가 아니라 **대상 클러스터의 리소스 총량**입니다 — controller는 대상 클러스터의 (거의) 모든 종류의 리소스를 watch·캐시합니다. CiliumEndpoint·Event·EndpointSlice처럼 수만 개 생기는 종류가 있으면 OOM으로 직결. 방어: `argocd-cm`의 `resource.exclusions`로 watch 범위를 좁히고(메모리와 대상 API 부하를 동시에 감소), 클러스터 수가 많으면 샤딩(consistent-hashing 등)으로 컨트롤러 인스턴스에 분배.

**A3.** "sync가 느리다" → repo-server: 매니페스트 렌더링(helm/kustomize) 대기열 — 동시성 제한과 캐시 미스가 원인입니다. "OutOfSync 감지가 늦다" → application-controller: reconcile 주기(기본 180초)와 리스트/watch 처리 지연 — 해법은 webhook 설정(커밋 즉시 refresh)과 watch 범위 축소, 필요 시 샤딩.

**A4.** [A] 중앙집중(ArgoCD 1개 → N 클러스터): 단일 UI·정책, 운영 단순 / SPOF, 자격증명 집중, 네트워크 경계 통과. [B] 허브-스포크(리전·환경별 ArgoCD): 폭발 반경 축소, 지연 감소 / 여러 ArgoCD의 버전·정책 일관성 관리 부담. [C] 클러스터별 ArgoCD: 최대 격리, self-manage 가능 / 전역 뷰 상실, 운영 대상 N배. 중앙집중의 숨은 대가: 대상 클러스터 자격증명(대개 cluster-admin 토큰)이 허브 Secret에 모이므로 **ArgoCD 침해 = 전 클러스터 침해**입니다.

**A5.** list(정적 목록), clusters(등록 클러스터 셀렉터), git(디렉터리 또는 파일 — 모노레포와 결합), matrix(곱집합), merge(병합·override), pullRequest(PR마다 프리뷰 환경). 구조적 위험: 생성기의 입력(라벨·디렉터리·PR 상태)이 바뀌면 Application이 **사라지고 워크로드까지 삭제**됩니다. 방어: `syncPolicy.applicationsSync: create-update`(삭제 금지)와 `preserveResourcesOnDeletion: true`(앱이 지워져도 리소스 유지), 그리고 변경 시 dry-run·PR 리뷰.

**A6.** app-of-apps: 루트 Application이 Git의 apps/ 디렉터리를 가리키고 그 안의 각 YAML이 또 다른 Application — 정적 목록이라 명시적이고 리뷰가 쉽습니다(부트스트랩·self-manage에 적합). ApplicationSet: 생성기로 앱을 동적 생성 — 확장성이 뛰어나지만 삭제 위험이 있습니다. 함께 쓰기: 루트/플랫폼 컴포넌트는 app-of-apps로 명시 관리, 팀별·클러스터별로 반복되는 앱은 ApplicationSet으로 생성.

**A7.** AppProject: **무엇을 어디에** — 허용 소스 저장소(sourceRepos), 배포 가능 목적지(클러스터·네임스페이스), 생성 가능 리소스 종류(clusterResourceWhitelist·namespaceResourceBlacklist). RBAC: **누가 무엇을** — 주체(SSO 그룹)별로 get·sync·delete·override 등의 행위를 프로젝트/앱 범위로 허용·거부. 둘 다 필요한 이유: RBAC만 있으면 앱이 kube-system에 배포하는 것을 못 막고, AppProject만 있으면 누가 prod를 sync하는지 통제하지 못합니다 — 반쪽 통제는 안심만 줍니다.

**A8.** ApplicationSet의 git 디렉터리 생성기가 `apps/*` 패턴으로 디렉터리를 스캔해 Application을 생성하고 있었습니다. 리팩터링 PR은 파일을 `apps/<service>/`에서 `apps/<team>/<service>/`로 **이동**시켰을 뿐이지만, 생성기 관점에서는 기존 매칭 경로들이 **사라진** 것입니다 → 대응하는 Application 47개가 삭제 대상이 되고 → `preserveResourcesOnDeletion`이 없어 각 앱의 리소스(PVC 포함)까지 정리됐습니다. 즉 생성기의 입력은 YAML 내용이 아니라 **디렉터리 구조 자체**이며, PR diff만 보는 리뷰는 그 변경의 의미를 볼 수 없었습니다.
