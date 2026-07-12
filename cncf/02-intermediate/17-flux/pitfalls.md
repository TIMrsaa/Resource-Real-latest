# 흔한 함정 5선

## 1. 이미지 자동화가 main에 직접 커밋하게 방치

`ImageUpdateAutomation`의 기본 유혹은 main 브랜치에 바로 커밋하는 것입니다 — 편하고, 새 이미지가 자동으로 프로덕션에 갑니다. 그리고 그 순간 cicd 24에서 세운 승인 게이트가 증발합니다(리뷰 없는 배포). 안전 패턴: `push.branch: image-updates`로 별도 브랜치에 커밋하고, GitHub Action으로 PR을 자동 생성해 리뷰·CI를 거치게 합니다. 자동화의 목적은 사람을 빼는 것이 아니라 **반복 작업을 빼고 판단은 남기는 것**입니다.

## 2. ImagePolicy를 느슨하게 (alphabetical·latest)

`policy.alphabetical: {order: asc}`는 `latest`나 예상 못 한 태그를 뽑을 수 있고, `numerical`은 태그 형식이 흔들리면 엉뚱한 것을 고릅니다. 프로덕션은 `semver: {range: ">=6.0.0 <7.0.0"}`처럼 메이저를 고정하거나, `filterTags`로 브랜치·커밋 패턴에서 정렬 키를 추출해야 합니다(예: `^main-[a-f0-9]+-(?P<ts>.*)$`). cicd 04의 태그 규율("태그는 움직인다")이 이미지 자동화에서 자동 배포 위험으로 되돌아옵니다 — 정책이 곧 게이트입니다.

## 3. 크로스 네임스페이스 참조를 막지 않음

멀티테넌시에서 `serviceAccountName` 임퍼소네이션을 걸어도, team-a의 Kustomization이 **다른 네임스페이스의 Source**를 참조할 수 있으면 경계가 샙니다(다른 팀의 저장소를 읽어 자기 네임스페이스에 배포). kustomize-controller와 helm-controller에 `--no-cross-namespace-refs=true`를 반드시 설정하세요. 그리고 임퍼소네이션 SA의 RBAC를 실제 필요 범위로 좁혀야 합니다 — 경계를 지키는 것은 Flux가 아니라 K8s RBAC이고, RBAC가 넓으면 Flux도 넓습니다.

## 4. UI가 없다는 사실을 나중에 발견

Flux는 웹 UI를 제공하지 않습니다(CLI와 CR status가 인터페이스입니다). 플랫폼 팀에게는 문제가 아니지만, "개발자가 자기 배포 상태를 본다"가 요구사항이면 별도 도구(Weave GitOps 계열, Grafana 대시보드, 또는 자체 포털 — 08의 Backstage)를 붙여야 합니다. 도입 결정 전에 물어라: **배포 상태의 소비자가 누구인가.** 플랫폼 팀만이면 `flux get`으로 충분하고, 수백 명의 개발자면 UI 계층이 별도 프로젝트가 됩니다.

## 5. HelmRelease의 remediation을 이해하지 못한 채 실패를 방치

`upgrade.remediation.remediateLastFailure: true`는 실패 시 이전 릴리스로 자동 롤백합니다 — 훌륭하지만, **차트의 훅이 이미 부작용을 냈다면 그것은 롤백되지 않습니다**(15의 교훈이 그대로). 그리고 롤백이 반복되면 "계속 실패하지만 계속 살아있는" 상태가 되어 아무도 눈치채지 못합니다. 반드시 notification-controller의 Alert로 실패를 슬랙·이슈로 보내고, `retries` 소진 후의 상태(`ReconciliationFailed`)를 모니터링하세요. 자동 교정은 관측과 짝일 때만 안전합니다.

## 실무 사고 사례

> 한 플랫폼 팀이 Flux의 이미지 자동화를 도입했습니다 — CI가 이미지를 push하면 Flux가 감지해 Git에 커밋하고 배포까지 자동으로 이어지는, 완전한 pull 루프였습니다. ImagePolicy는 `numerical: {order: asc}`에 `filterTags`로 `main-<sha>-<timestamp>` 패턴에서 타임스탬프를 뽑도록 설정했고, 커밋은 main 브랜치에 직접 들어갔습니다. 여섯 달간 완벽하게 돌았습니다. 사고는 한 개발자가 실험용으로 `main-abc123-99999999999`라는 태그를 수동으로 push하면서 일어났습니다(타임스탬프 자리에 큰 숫자를 넣어 정렬 테스트를 하고 있었습니다). ImagePolicy는 그것을 "가장 최신"으로 판정했고, ImageUpdateAutomation이 main에 커밋했으며, Kustomization이 적용했습니다 — 실험용 이미지가 프로덕션 결제 서비스에 배포됐습니다. PR도, 리뷰도, 승인도 없었습니다. 3분 뒤 헬스체크 실패로 롤백됐지만(Flux가 이전 상태로 수렴하지 않았습니다 — Git이 진실이므로 그 나쁜 커밋이 계속 적용됐습니다) 실제 복구는 사람이 Git을 revert하고서였습니다. 12분간 결제가 실패했습니다. 개선은 세 겹이었습니다: ① 이미지 자동화 커밋을 별도 브랜치로 보내고 PR 자동 생성 + CI 통과 필수(승인 게이트 복원 — cicd 24). ② ImagePolicy를 semver로 전환하고, 태그 네이밍을 CI만 생성 가능하게 레지스트리 정책으로 제한. ③ Kustomization에 `healthChecks`와 notification Alert를 걸어 실패가 즉시 사람에게. 회고의 문장이 이 모듈의 요지였습니다: "**우리는 pull 루프를 닫으면서 승인 게이트도 함께 닫아버렸습니다** — GitOps의 '자동'은 배포의 자동이지 판단의 자동이 아닙니다."
