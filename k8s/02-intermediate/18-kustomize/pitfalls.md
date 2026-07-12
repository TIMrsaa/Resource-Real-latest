# 흔한 함정 5선

## 1. base를 직접 고쳐서 환경 차이 만들기

"prod만 급하니까 base의 replicas를 3으로" — 그 순간 dev도 3이 됩니다. 환경 차이는 **반드시 오버레이 패치로.** base 수정은 "모든 환경에 적용돼야 하는 변경"일 때만.

## 2. 제너레이터 해시를 끄는 습관

`generatorOptions: { disableNameSuffixHash: true }` 를 "이름이 지저분해서" 켜는 경우 — 자동 롤링이라는 핵심 가치를 버리는 것입니다. 해시를 꺼야 하는 경우(외부 시스템이 고정 이름 참조)가 아니면 켜두라. 부작용인 "옛 CM 잔존"은 prune 기능이나 GitOps 도구가 정리합니다.

## 3. namePrefix/Suffix와 하드코딩 참조의 충돌

Kustomize는 자기가 아는 참조(Deployment→CM/Secret/SA 등)는 이름 변경을 따라가지만, **문자열 안의 참조**(env 값에 박은 Service 이름, ConfigMap 데이터 속 URL)는 못 따라갑니다. nameSuffix를 붙였더니 앱이 옛 이름을 찾는 사고 — 이름은 가능하면 참조 필드로, 문자열 참조는 vars/replacements로 명시.

## 4. JSON6902 패치의 배열 인덱스 취약성

`/spec/template/spec/containers/0/...` — base에 컨테이너가 추가되면 0번이 다른 컨테이너가 될 수 있습니다. 컨테이너 수정은 strategic merge(name 매칭)가 안전하고, 6902는 strategic이 못 하는 연산(remove 등)에 한정.

## 5. kubectl 내장 버전의 지연

kubectl 내장 kustomize는 독립 CLI보다 버전이 뒤처집니다 — 최신 필드(components, replacements 등)가 안 먹을 수 있습니다. 새 기능을 쓰면 팀 전체가 독립 `kustomize` CLI 버전을 맞추거나, CI에서 빌드 결과를 검증하세요.

## 실무 사고 사례

> dev 오버레이에서 잘 되던 변경을 prod에 적용 — 그런데 prod 오버레이에는 6902 패치가 `containers/0`의 이미지를 바꾸고 있었고, 이번 변경으로 base의 0번 자리에 사이드카가 추가되면서 **사이드카의 이미지가 앱 이미지로 교체**됐습니다. 렌더링 결과 검토 없이 apply한 것이 화근. 교훈: **PR에 `kubectl kustomize overlays/prod`의 diff를 첨부하는 CI를 두라** — 렌더링 결과가 곧 배포 내용입니다.
