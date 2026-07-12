# 자가 점검 퀴즈

**Q1.** Flux의 다섯 컨트롤러를 나열하고, ArgoCD의 구조와 철학적으로 어떻게 다른가?

**Q2.** Flux의 GitRepository와 Kustomization 분리가 주는 이점은? ArgoCD Application과 비교하세요.

**Q3.** OpenGitOps 4원칙을 쓰고, 이것이 "도구는 구현, 원칙이 본질"과 어떻게 연결되나요?

**Q4.** Flux 이미지 자동화의 세 리소스와 그 역할은? 14의 어떤 경계를 해결하나요?

**Q5.** 이미지 자동화를 프로덕션에 쓸 때의 위험과 통제 방법은?

**Q6.** ArgoCD와 Flux 중 하나를 고르는 기준을 "설계 철학"으로 설명하세요.

**Q7.** 완전 자동 GitOps 파이프라인에서 CI의 책임은 어디서 끝나는가요? 왜 그것이 보안적으로 좋은가요?

**Q8.** "ArgoCD를 깔았으니 GitOps다"가 왜 틀릴 수 있는가요?

---

## 정답

**A1.** source-controller(git/helm/oci 가져오기), kustomize-controller(적용), helm-controller(Helm), image-reflector+image-automation-controller(이미지 자동화), notification-controller(알림). ArgoCD는 하나의 큰 애플리케이션+강력한 UI(배포 플랫폼)인 반면, Flux는 작은 전문 컨트롤러들의 조합(유닉스 철학의 툴킷)입니다.

**A2.** source(가져오기)와 apply(적용)가 분리되어 **하나의 GitRepository를 여러 Kustomization이 공유**할 수 있습니다 — git을 한 번만 폴링해 fleet의 여러 앱에 적용(대역폭·부하 절감), source 종류 교체 용이. ArgoCD의 Application은 이 둘을 통합하므로 Application마다 source를 갖습니다.

**A3.** ① 선언적 ② git 버전관리·불변 ③ 자동으로 pull ④ 지속 reconcile. ArgoCD든 Flux든 이 네 원칙을 구현할 뿐이므로 — 도구를 바꿔도 원칙은 그대로이고(12의 이식성 GitOps판), 새 도구나 자체 구축도 이 원칙으로 평가·설계할 수 있습니다. 본질은 원칙이지 특정 도구가 아닙니다.

**A4.** ① ImageRepository(레지스트리 스캔 — 태그 발견) ② ImagePolicy(어떤 태그를 고를지 — semver 등) ③ ImageUpdateAutomation(선택된 이미지로 git 자동 커밋). 14의 경계 ②("이미지 태그를 누가 git에 업데이트하나")를 내장으로 해결 — CI는 이미지 push만, Flux가 git 갱신을 대신합니다.

**A5.** 위험: policy가 "최신 태그"로 열려 있으면 검증 안 된/실수한 이미지가 자동으로 프로덕션 배포됩니다(그리고 "누가 배포했나"가 봇이라 원인 추적이 흐려짐). 통제: 프로덕션은 명시적 semver 범위, 자동 갱신 대신 staging 검증 후 승격 PR, 환경별 policy 분리, 프리릴리스 제외.

**A6.** ArgoCD: 하나의 앱+강력한 UI — 배포 상태를 시각적으로 보는 문화, 개발자 셀프서비스 대시보드에 적합. Flux: 컨트롤러 조합(툴킷) — 이미지 자동화 내장, 조합·확장·다른 도구 통합, CLI/GitOps 순수주의에 적합. 우열이 아니라 팀 문화와 설계 선호의 문제(둘 다 CNCF Graduated·프로덕션급).

**A7.** CI는 **이미지 빌드 + 레지스트리 push**에서 끝납니다 — git이나 클러스터를 건드리지 않습니다(이미지 자동화가 git 갱신을, CD 컨트롤러가 배포를 담당). 보안적 이점: 파이프라인이 클러스터 자격증명은 물론 git 쓰기 권한조차 최소화되어, 파이프라인 탈취 시 피해가 레지스트리 push로 제한됩니다(그마저 policy·환경 분리로 통제).

**A8.** GitOps는 도구가 아니라 OpenGitOps 4원칙(선언·git 버전관리·자동 pull·지속 reconcile)입니다. ArgoCD를 깔고도 사람들이 여전히 kubectl로 배포하거나(selfHeal 끄고), 시크릿을 클러스터에 직접 만들거나, git 없이 UI로 변경하면 — 원칙이 지켜지지 않아 GitOps가 아닙니다. 도구는 원칙을 돕는 것이고, 규율이 본질입니다.
