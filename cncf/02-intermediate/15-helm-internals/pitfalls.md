# 흔한 함정 5선

## 1. HPA가 있는데 차트에 replicas를 둡니다

HPA가 live의 replicas를 5로 올려도, `helm upgrade`에서 values의 replicaCount(2)가 old와 달라지는 순간 Helm이 2로 덮어씁니다 — 그리고 HPA가 다시 올리고, 다음 배포에서 또 덮입니다. 진동입니다. 원인은 3-way 병합이 아니라 **필드 소유권**의 혼란입니다(cicd 14의 그 문제): replicas의 주인이 HPA인데 차트가 선언하고 있습니다. 해법은 차트에서 replicas를 제거하는 것(또는 `{{- if not .Values.autoscaling.enabled }}`로 조건부). 잘 만들어진 차트가 그렇게 하는 이유입니다 — 도구가 아니라 소유권을 설계하세요.

## 2. `--force`를 습관적으로 사용

업그레이드가 안 먹을 때 `--force`를 붙이면 대개 "된다" — 3-way 병합을 건너뛰고 replace하기 때문입니다. 그 대가로 다른 컨트롤러가 소유한 필드(HPA의 replicas, 서비스의 clusterIP, 사이드카 주입 결과)가 날아가고, 리소스가 삭제·재생성되어 다운타임이 생길 수 있습니다. `--force`는 진단 도구가 아니라 최후 수단이며, 그 전에 물어야 합니다: 왜 병합이 원하는 결과를 못 내는가(대개 필드 소유권 문제이고, 그러면 ①의 해법이 맞습니다).

## 3. 훅의 delete-policy를 명시하지 않음

훅 리소스는 **릴리스 매니페스트에 포함되지 않습니다**(lab-02 Step 3에서 확인) — `helm uninstall`을 해도 남고, 다음 훅 실행 시 "이미 존재함" 에러를 냅니다. `hook-delete-policy`를 반드시 명시하세요: `before-hook-creation`(다음 실행 전 정리, 기본 권장), `hook-succeeded`(성공 시 삭제), `hook-failed`(실패 시 삭제 — 디버깅하려면 빼둡니다). 그리고 더 근본적인 문제: **훅이 실패해도 이미 발생한 부작용(마이그레이션)은 롤백되지 않습니다** — 마이그레이션은 멱등·전진 호환(expand-contract, cicd 11)으로 설계해야 하며, 훅은 순서만 보장합니다.

## 4. helm CLI와 GitOps 컨트롤러가 같은 릴리스를 동시에 관리

누군가 급하게 `helm upgrade`로 핫픽스를 하고, ArgoCD가 다음 sync에서 되돌리고, 다시 helm으로 고치는 루프 — 두 진실(릴리스 Secret vs Git)이 싸우는 전형입니다(lab-02 Step 4). 조직은 셋 중 하나로 통일해야 합니다: ArgoCD 방식(helm은 템플릿 엔진, Git이 유일 진실), Flux 방식(HelmRelease CR로 컨트롤러가 릴리스 관리), CI 렌더(완성 매니페스트를 Git에). 어느 쪽이든 **"사람이 helm CLI로 프로덕션을 만지지 않는다"**가 규율이고, 예외는 break-glass 절차(cicd 24)로.

## 5. `crds/` 디렉터리를 일반 템플릿처럼 기대

Helm의 `crds/`는 특별 취급됩니다 — 템플릿 렌더링이 되지 않고(`{{ }}` 안 통함), 설치 시에만 생성되며, **upgrade와 uninstall에서 건드리지 않습니다**. "차트를 업그레이드했는데 CRD 새 필드가 없어요"의 원인이 대개 이것입니다. 의도된 안전장치입니다(CRD 삭제는 그 CR 데이터를 전부 날립니다). CRD 버전 업그레이드는 별도 절차로 계획하세요: 수동 `kubectl apply`, 별도 차트, 또는 오퍼레이터의 CRD 관리 기능. 그리고 CRD를 `templates/`에 두는 우회는 삭제 위험을 부르므로 신중히.

## 실무 사고 사례

> 한 팀이 결제 서비스를 Helm으로 배포했습니다. 어느 금요일 저녁, 트래픽 급증으로 온콜이 `kubectl scale deploy/payment --replicas=20`을 했습니다 — 정상적인 응급 조치였고, 서비스는 살아났습니다. 월요일 아침, 무관한 설정 변경(로그 레벨)을 위해 누군가 `helm upgrade --set logLevel=debug`를 실행했습니다. 그 순간 replicas가 **차트 기본값 3으로 되돌아갔습니다** — values의 replicaCount는 old도 new도 3이었지만, 다른 필드가 바뀌며 Deployment 오브젝트 전체가 패치 대상이 됐고, Helm의 병합 결과가 3을 적었습니다. 월요일 오전 트래픽에 3개의 Pod가 맞았고, 4분간 결제 실패가 이어졌습니다. 사후 분석에서 세 가지가 드러났습니다: ① replicas의 소유자가 불분명했습니다(HPA가 있었지만 minReplicas=3이었고, 차트도 replicas를 선언했습니다). ② 응급 조치가 Git·values에 반영되지 않아 "클러스터의 진실"과 "Helm의 진실"이 갈라진 채 이틀을 보냈습니다. ③ 아무도 `helm diff upgrade`(플러그인)로 사전 확인을 하지 않았습니다. 개선은 셋이었습니다: 차트에서 replicas 제거하고 HPA에 위임(필드 소유권 명확화), 응급 조치 후 반드시 Git에 반영하는 절차(break-glass의 사후 정리 — cicd 24), 그리고 CI의 배포 파이프라인에 `helm diff upgrade`를 필수 게이트로(무엇이 바뀔지 사람이 승인). 교훈: **3-way 병합은 훌륭한 알고리즘이지만, 필드의 주인이 여럿이면 어떤 알고리즘도 옳은 답을 낼 수 없습니다** — Helm을 이해한다는 것은 "누가 무엇을 소유하는가"를 설계하는 일입니다.
