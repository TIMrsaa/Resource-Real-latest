# 흔한 함정 5선

## 1. cluster-admin 남발

"권한 에러 귀찮은데 그냥 cluster-admin" — 그 Binding 하나가 보안 모델 전체를 무효화합니다. CI 봇이 cluster-admin이면 CI 침해 = 클러스터 전체 장악. 에러가 난 동사/리소스만 추가하는 습관(`auth can-i --list`로 진단).

## 2. default SA에 권한 부여

default SA는 **그 ns의 모든 미지정 Pod**가 씁니다. 여기에 권한을 주면 "잊힌 Pod"들이 전부 그 권한을 갖습니다. 권한이 필요한 워크로드마다 전용 SA. 그리고 API 안 쓰는 앱은 `automountServiceAccountToken: false`.

## 3. 401과 403을 구분 안 함

- **401 Unauthorized = 인증 실패** ("너 누군지 모르겠어") → IAM/토큰/kubeconfig 문제
- **403 Forbidden = 인가 실패** ("누군지 아는데 권한 없어") → RBAC 문제

이 구분만 해도 디버깅 방향이 반대가 됩니다. 메시지를 읽어라 — 거부 메시지에 User명과 부족한 verb/resource가 다 적혀 있습니다.

## 4. 읽기 권한에 secrets 포함

`resources: ["*"]` 또는 view를 흉내 내며 secrets를 넣는 실수. secrets 읽기 = 그 ns의 모든 자격증명 열람입니다. 내장 view가 secrets를 뺀 이유를 기억하고, secrets 접근은 별도 Role로 분리해 꼭 필요한 주체에게만.

## 5. escalation 방어를 모르고 당황

"edit 권한이 있는데 왜 RoleBinding을 못 만들죠?" — RBAC에는 **권한 상승 방지**가 내장돼 있습니다: 자기가 갖지 않은 권한을 남에게 부여할 수 없습니다(escalate/bind verb가 없는 한). 버그가 아니라 설계입니다.

## 실무 사고 사례

> 개발 편의로 모든 팀원에게 cluster-admin을 줬던 스타트업. 퇴사자의 노트북에 남은 kubeconfig + 만료 없는 인증서로 몇 달 뒤에도 클러스터 접근이 가능했음이 감사에서 발견. 교훈: ① 인증서 기반 사용자 발급 금지(폐기 불가) — IAM/OIDC처럼 **중앙에서 끌 수 있는** 인증으로 ② 권한은 그룹 단위, 입퇴사는 IdP에서 ③ 분기마다 `kubectl get clusterrolebindings -o wide` 감사.
