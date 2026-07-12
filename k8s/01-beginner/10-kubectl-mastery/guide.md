# 학습 가이드 — kubectl을 "암기"에서 "탐색"으로

## 관점 전환

kubectl 명령 수백 개를 외우는 사람은 없습니다. 고수와 초심자의 차이는 **모르는 것을 그 자리에서 알아내는 루틴**입니다:

```
리소스 종류가 궁금합니다  → kubectl api-resources
필드가 궁금합니다        → kubectl explain <kind>.<path> [--recursive]
지금 값이 궁금합니다      → kubectl get -o yaml / jsonpath
바꾸면 어떻게 되나      → kubectl diff -f / --dry-run=server
왜 안 되나            → describe → events → logs --previous → debug
```

이 루틴 자체가 이 모듈의 내용입니다. 외울 것은 명령이 아니라 루틴입니다.

## 우선순위 가이드

매일 쓰는 것(반사신경 수준으로): `get -o wide/yaml`, `describe`, `logs -f --previous`, `exec -it`, `apply -f`, `explain`
주 1회쯤: jsonpath, custom-columns, patch, port-forward, debug
알면 한 방인 것: `diff`, `--dry-run=server`, `events --sort-by`, `auth can-i`

## 효율 도구 (선택)

```bash
alias k=kubectl
# 자동완성 (bash 기준)
source <(kubectl completion bash); complete -o default -F __start_kubectl k
# 컨텍스트/ns 빠른 전환: kubectx / kubens (설치형)
```

> 단, 자격증(CKA) 환경에서도 alias와 자동완성은 기본 제공됩니다 — 의존해도 좋습니다.
