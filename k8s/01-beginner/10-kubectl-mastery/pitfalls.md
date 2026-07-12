# 흔한 함정 5선

## 1. edit/patch로 고치고 Git에 반영 안 함

라이브 수정은 다음 `apply`/배포 파이프라인에서 **조용히 원복**됩니다 — "분명 고쳤는데 또 장애". 긴급 수정 후에는 반드시 같은 변경을 YAML(Git)에도. GitOps 환경(ArgoCD)은 아예 즉시 되돌려버립니다(self-heal) — 모듈 39.

## 2. `kubectl delete -f dir/`의 사각지대

디렉터리로 apply하다가 파일 하나를 **삭제**한 경우, `apply -f dir/`는 그 리소스를 지워주지 않습니다(파일이 없으니 모름). 고아 리소스 발생. 해결: `apply --prune`(주의 깊게) 또는 Kustomize/Helm/GitOps가 삭제까지 추적.

## 3. jsonpath 인용 지옥 (특히 Windows)

라벨 키에 점이 있으면 이스케이프 필요: `{.metadata.labels.app\.kubernetes\.io/name}`. PowerShell에서는 작은따옴표/큰따옴표 규칙이 bash와 달라 jsonpath가 자주 깨집니다 — 복잡한 추출은 `-o json | jq` 또는 파일로 빼서 처리.

## 4. `--force --grace-period=0` 남용

강제 삭제는 "kubelet의 확인 없이 etcd에서 지우는 것"입니다. StatefulSet에서 쓰면 같은 ID의 Pod가 두 개 살아있는 split-brain 위험(모듈 19). Terminating에 갇힌 원인(볼륨 분리 지연, finalizer, 노드 죽음)을 먼저 봐야 합니다.

## 5. 컨텍스트 착각 — prod에서 dev 명령

멀티 클러스터에서 가장 비싼 실수. `kubectl config current-context`를 프롬프트에 표시(kube-ps1)하거나, prod 컨텍스트는 읽기 전용 권한으로 분리하세요. "kubectl delete ns ..." 입력 전 1초의 컨텍스트 확인이 경력을 구합니다.

## 실무 사고 사례

> 운영 중 HPA 이상으로 replicas를 `kubectl edit`으로 급히 수정한 엔지니어. 사건 종료 후 Git 반영을 잊었고, 2주 뒤 정기 배포가 옛 값으로 덮어쓰며 같은 장애 재발 — 이번엔 새벽. 교훈: **라이브 수정은 빚입니다. 갚기(Git 반영) 전까지 사건은 끝난 게 아닙니다.** 사후 점검 체크리스트에 "수동 변경 Git 반영 여부"를 넣어라.
