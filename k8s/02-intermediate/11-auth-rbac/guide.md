# 학습 가이드 — RBAC는 4개 리소스의 조합 퍼즐

## 큰 그림 먼저

```
요청 → ① 인증(Authentication): "너 누구야?"     — 인증서/토큰/IAM
     → ② 인가(Authorization): "그거 해도 돼?"    — RBAC가 여기
     → ③ Admission: "규정에 맞아?"               — 모듈 23
```

RBAC의 재료는 단 4가지, 조합 공식은 하나입니다:

```
[무엇을 할 수 있나]      [누가]
Role (ns 한정)      ×    User / Group / ServiceAccount
ClusterRole (전역)        를
        └── Binding이 연결합니다 (RoleBinding=ns 범위, ClusterRoleBinding=전역)
```

헷갈림 방지 규칙: **권한의 "내용"은 Role류가, 권한의 "적용 범위"는 Binding이 결정합니다.** ClusterRole을 RoleBinding으로 묶으면 "전역 정의를 한 ns에만 적용" — 이 조합이 실무 표준입니다 (공통 Role 재사용).

## K8s의 독특한 점: User 리소스가 없습니다

`kubectl get users` 는 없습니다. K8s는 사용자 DB를 **갖지 않고**, 인증서의 CN이나 IAM 같은 외부 신원을 "문자열"로 신뢰합니다. EKS에서는 **IAM이 사용자 DB**입니다 — access entries가 IAM↔K8s 그룹을 매핑합니다. 이 구조를 이해하면 "사용자 추가"가 왜 IAM 작업인지 명확해집니다.

## 학습 전략

- lab-01에서 권한이 "안 되는" 상태를 먼저 만들고 하나씩 열어가라. 거부 메시지(`forbidden`)를 많이 보는 것이 학습입니다.
- `kubectl auth can-i --as=` 는 권한 설계의 단위 테스트입니다. Binding을 만들 때마다 can-i로 검증하는 습관.
- 최소 권한의 황금률: **verbs도 resources도 와일드카드(*) 금지**, secrets는 별도 Role로 분리.
