# 흔한 함정 5선

## 1. 렌더링 안 보고 install

들여쓰기 한 칸 어긋난 YAML이 "유효한 YAML이지만 의미가 다른" 채로 배포되는 경우(예: env가 컨테이너 밖에 붙음). `helm template`을 먼저, 운영 전엔 `helm diff upgrade`. 템플릿 작성 중에는 `--debug --show-only templates/deployment.yaml`로 한 파일만 보며 작업.

## 2. --set으로 운영 설정 누적

`--set`은 휘발성입니다 — 다음 upgrade에서 그 값을 빼먹으면 조용히 원복. 운영 값은 전부 values-prod.yaml(Git)에. `helm get values <release>`로 "지금 적용된 값"을 정기 대조하세요.

## 3. helm과 kubectl의 이중 관리

helm으로 설치한 리소스를 kubectl edit으로 고치면, 다음 upgrade의 3-way merge가 예상 밖 결과를 만들 수 있습니다(수동 변경이 유지되기도, 덮이기도). 원칙: **helm 릴리스는 helm으로만.** 긴급 수동 변경 후엔 차트/values에 반영하고 upgrade로 정합 회복.

## 4. CRD의 특수 취급을 모름

차트의 `crds/` 디렉터리는 install 시 한 번 깔리고 **upgrade에서 갱신되지 않으며 uninstall에도 안 지워집니다** (데이터 보호 목적의 의도된 동작). "차트 업그레이드했는데 새 CRD 필드가 없다"의 원인. CRD 업그레이드는 별도 절차(`kubectl apply`)로.

## 5. 차트 version과 appVersion 혼동

`version`은 **차트 자체**의 semver(템플릿 변경 시 올림), `appVersion`은 담긴 앱의 버전(관례상 기본 이미지 태그). 이미지 태그만 바꾸면서 차트 version을 안 올리면 차트 저장소에서 "같은 버전, 다른 내용"이라는 최악의 상태가 됩니다.

## 실무 사고 사례

> 운영 중 helm upgrade가 "another operation is in progress" 로 영영 안 풀리는 상태가 됐습니다 — 이전 CI 작업이 타임아웃으로 죽으며 릴리스가 `pending-upgrade`로 방치된 것. 담당자가 당황해 릴리스 Secret을 수동 삭제했고 helm이 이력을 잃어 이후 upgrade가 전부 충돌. 정석은 `helm rollback <release> <마지막 정상 revision>` (pending 해소) 또는 helm 진단 후 잠금만 해제하는 것이었습니다. 교훈: **CI의 helm에는 --timeout과 --atomic을 항상 같이** — pending 좀비를 만들지 않는 것이 최선의 예방.
