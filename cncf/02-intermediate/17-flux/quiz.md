# 자가 점검 퀴즈

**Q1.** "제품(ArgoCD) vs 툴킷(Flux)"의 설계 차이를 컨트롤러·CRD 구조로 설명하세요.

**Q2.** GitOps Toolkit의 컨트롤러 4종과 각 CRD는? "소스와 적용의 분리"가 주는 이점 두 가지는?

**Q3.** Flux의 `dependsOn`은 ArgoCD의 무엇에 대응하나요? 둘의 층 차이는?

**Q4.** HelmRelease가 15의 "두 진실 문제"를 푸는 방식은? ArgoCD 방식과의 트레이드오프는?

**Q5.** 이미지 자동화의 세 CRD와 그 루프를 설명하세요. cicd 14의 어떤 개념의 완성형인가요?

**Q6.** ImagePolicy의 정책 종류와 각각의 위험은? 프로덕션 권장은?

**Q7.** Flux의 테넌시 경계는 무엇이 강제하나요? 반드시 켜야 할 플래그와 그 이유는?

**Q8.** 사고 사례에서 "pull 루프를 닫으면서 승인 게이트도 닫았다"는 무슨 뜻이고, 어떻게 복원하나요?

---

## 정답

**A1.** ArgoCD: Application CRD 하나 + 큰 컨트롤러 하나 + 강력한 UI — 설치하면 GitOps 제품이 완성됩니다. Flux: GitRepository/OCIRepository/Kustomization/HelmRelease/ImagePolicy 등 다수의 독립 CRD + 각각의 독립 컨트롤러 + UI 없음 — GitOps를 지을 부품(툴킷)을 제공합니다. 결과: Flux는 조합이 자유롭고 다른 프로젝트(Flagger 등)가 라이브러리로 재사용하지만, 개념을 여럿 알아야 하고 상태를 한 화면에서 보려면 도구를 붙여야 합니다.

**A2.** source-controller(GitRepository/HelmRepository/OCIRepository/Bucket/HelmChart — 아티팩트 fetch·검증·서빙), kustomize-controller(Kustomization — build·apply·prune·healthChecks), helm-controller(HelmRelease — 실제 Helm 릴리스 관리), notification-controller(Alert/Provider — 아웃바운드, Receiver — 인바운드 웹훅). 분리의 이점: ① 한 소스를 여러 적용이 공유(clone·fetch 한 번, 여러 목적) ② 각 적용이 자기 주기·경로·의존성을 가져 세밀한 제어가 가능합니다.

**A3.** ArgoCD의 sync wave(리소스 어노테이션 `argocd.argoproj.io/sync-wave`)에 대응합니다. 층 차이: sync wave는 **한 Application 안에서 리소스들의 적용 순서**를 정하는 어노테이션이고, `dependsOn`은 **Kustomization CR 사이의 의존성**(다른 CR이 Ready여야 적용)을 정하는 CR 필드입니다. 즉 Flux는 조정 단위 자체를 그래프로 묶고, ArgoCD는 앱 내부 리소스를 웨이브로 묶습니다(ArgoCD도 app-of-apps로 앱 간 순서를 흉내낼 수 있습니다).

**A4.** Flux는 HelmRelease CR을 Git에 두고 helm-controller가 **실제 Helm 릴리스**를 생성·관리합니다 — 릴리스 Secret이 존재하므로 `helm history`·`helm rollback`이 유효하고 차트의 훅이 온전히 동작하며, `upgrade.remediation`으로 실패 시 자동 롤백까지 합니다. ArgoCD는 `helm template`으로 렌더링만 하고 릴리스를 만들지 않아 Git이 유일한 진실이지만 helm의 상태 기계를 잃습니다. 트레이드오프: Flux는 Helm의 능력을 살리는 대신 "클러스터에 실제로 무엇이 갔는가"의 diff가 릴리스를 거쳐야 보이고, ArgoCD는 diff가 직접적인 대신 rollback을 Git revert로 해야 합니다.

**A5.** ImageRepository(레지스트리의 태그 목록을 주기적으로 스캔 — 이미지를 pull하지 않고 메타데이터만) → ImagePolicy(정책으로 최신 태그 선택: semver/numerical/alphabetical + filterTags) → ImageUpdateAutomation(선택된 태그를 Git의 매니페스트 마커 위치에 써넣고 커밋·푸시). 루프: CI가 이미지 push → Flux가 감지 → Git 커밋 → GitRepository가 감지 → Kustomization이 적용. 이것은 cicd 14의 **push→pull 역전**의 완성형입니다 — CI는 레지스트리까지만 관여하고, 배포는 클러스터가 당깁니다.

**A6.** semver(range 지정 — 메이저 고정, 안전, 프로덕션 권장), numerical(숫자 정렬 — 태그 형식이 흔들리면 엉뚱한 것 선택), alphabetical(문자 정렬 — `latest`가 뽑힐 수 있어 위험). 보완: `filterTags`로 브랜치·커밋 태그에서 정렬 키를 정규식으로 추출(`^main-[a-f0-9]+-(?P<ts>.*)$`). 느슨한 정책은 원치 않는 이미지의 자동 프로덕션 배포로 직결되며(사고 사례), 정책이 곧 게이트입니다.

**A7.** **K8s RBAC**가 강제합니다 — Kustomization/HelmRelease의 `serviceAccountName`으로 임퍼소네이션하면 그 SA의 RBAC를 넘는 리소스 생성이 API 서버에서 거부됩니다(ArgoCD는 중앙 서버의 AppProject·RBAC가 판단). 반드시 켤 플래그: kustomize-controller·helm-controller의 `--no-cross-namespace-refs=true` — 이것이 없으면 team-a의 Kustomization이 다른 네임스페이스의 Source를 참조해 경계를 우회할 수 있습니다. 그리고 임퍼소네이션 SA의 RBAC를 실제 필요 범위로 좁혀야 합니다.

**A8.** 이미지 자동화가 main 브랜치에 직접 커밋하면, 새 이미지가 리뷰·승인·CI 없이 프로덕션에 도달합니다 — GitOps의 "Git이 진실"은 유지되지만 그 Git에 무엇이 들어가는지를 아무도 검토하지 않게 됩니다(실험용 태그가 결제 서비스에 배포된 사고). 복원: ① `push.branch`로 별도 브랜치에 커밋하고 PR 자동 생성 → CI·리뷰·승인(cicd 24)을 거쳐 main으로. ② ImagePolicy를 semver로 좁히고 태그 네이밍을 CI만 생성 가능하게 레지스트리 정책으로 제한. ③ healthChecks + notification Alert로 실패가 즉시 사람에게. 원칙: **GitOps의 '자동'은 배포의 자동이지 판단의 자동이 아닙니다.**
