# 퀴즈 — 07. Storage & IRSA

### Q1. IRSA의 핵심 메커니즘은?

A. Pod IP 와 IAM 정책 매핑
B. K8s SA 토큰 → STS AssumeRoleWithWebIdentity → IAM 임시 자격증명
C. 노드 IAM Role 공유
D. AWS Secrets Manager 자동 사용

---

### Q2. IRSA를 위해 클러스터에 필요한 전제 조건은?

A. AWS LB Controller
B. CoreDNS DNS 활성화
C. OIDC Identity Provider 등록
D. Pod Identity Agent

---

### Q3. IRSA 의 IAM Role Trust Policy 의 핵심 Condition 은?

---

### Q4. Pod Identity 가 IRSA 보다 좋은 점 두 가지를 적으세요.

---

### Q5. `eksctl create iamserviceaccount` 가 만드는 자원 두 가지는?

---

### Q6. Pod 안에서 IRSA 토큰의 위치는?

A. `/etc/aws/credentials`
B. `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
C. `~/.aws/credentials`
D. 환경변수에 직접 토큰 값

---

### Q7. IRSA 적용한 Pod 에서 호출이 `AccessDenied` 인데 IAM Role 에 정책은 분명히 있다. 점검 1순위는?

---

### Q8. Pod Identity 의 IAM Role 의 Trust 정책이 신뢰하는 Service 는?

---

### Q9. 같은 IAM Role 을 IRSA 로 NS A의 sa-1, NS B의 sa-2 에 모두 매핑하려면?

A. Trust Policy 의 sub Condition 을 OR 형태로 두 개 작성
B. IAM Role 을 두 개 만들기
C. Pod Identity 로 전환
D. (A)와 (C) 모두 가능

---

### Q10. (실습 검증) 현재 클러스터에서 IRSA 어노테이션이 붙은 모든 SA 를 한 번에 조회하는 명령은?

---

## 정답

<details>

**Q1**: B
**Q2**: C
**Q3**: `<oidc-issuer>:sub` 가 `system:serviceaccount:<ns>:<sa>` 와 정확히 일치
**Q4**: Trust 정책 단순 (OIDC sub 박지 않아도 됨), Role 재사용 쉬움 (Association 만 추가)
**Q5**: IAM Role (CFN Stack) + K8s ServiceAccount (annotation 자동 셋업)
**Q6**: B
**Q7**: SA 이름/네임스페이스가 IAM Role Trust 의 sub 조건과 정확히 일치하는지 (오타 가능성). 또는 자격증명 캐싱 — Pod 재시작.
**Q8**: `pods.eks.amazonaws.com`
**Q9**: D
**Q10**: `kubectl get sa -A -o json | jq '.items[] | select(.metadata.annotations."eks.amazonaws.com/role-arn") | "\(.metadata.namespace)/\(.metadata.name) -> \(.metadata.annotations."eks.amazonaws.com/role-arn")"' -r`

</details>

다음: [pitfalls.md](./pitfalls.md)
