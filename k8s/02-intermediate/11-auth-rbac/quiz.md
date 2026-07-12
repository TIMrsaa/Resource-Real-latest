# 자가 점검 퀴즈

**Q1.** `kubectl get users`가 없는 이유는?

**Q2.** 401과 403의 차이와 각각의 디버깅 방향은?

**Q3.** "공통 읽기 권한 정의를 만들어 여러 ns에 선별 적용"하려면 어떤 리소스 조합인가요?

**Q4.** 내장 ClusterRole `view`에 secrets가 빠진 이유는?

**Q5.** `pods/exec`에 create 권한을 주는 것이 왜 사실상 더 큰 권한 부여인가요?

**Q6.** Pod 안에서 K8s API를 호출하는 데 필요한 것 3가지(파일/객체)는?

**Q7.** EKS에서 신규 입사자에게 클러스터 읽기 권한을 주는 현대적 절차는?

**Q8.** RBAC에 deny 규칙이 없는데 어떻게 "거부"가 구현되는가요?

---

## 정답

**A1.** K8s는 사용자 DB를 갖지 않습니다. 인증 계층(인증서/OIDC/IAM)이 만들어낸 신원 문자열을 그대로 신뢰하며, RBAC는 그 문자열에 바인딩될 뿐입니다.

**A2.** 401=인증 실패(누군지 모름) → 자격증명/토큰/kubeconfig를 봅니다. 403=인가 실패(누군지 알지만 권한 없음) → RBAC Binding을 봅니다.

**A3.** **ClusterRole**(전역 정의) + 각 ns의 **RoleBinding**(ns 한정 적용).

**A4.** secrets 읽기는 해당 ns의 모든 자격증명 열람과 같아서, "읽기 전용"의 의도(관찰)를 초과하는 민감 권한이기 때문.

**A5.** exec로 컨테이너에 들어가면 그 Pod에 마운트된 **SA 토큰을 탈취**할 수 있어, 결과적으로 그 SA의 모든 권한을 얻는 것과 같습니다.

**A6.** ① 자동 마운트된 토큰 파일(`/var/run/secrets/.../token`) ② API 서버 주소(`kubernetes.default.svc`) ③ 그 SA에 권한을 준 **Role+RoleBinding** (없으면 403).

**A7.** IAM 사용자/역할 준비 → `aws eks create-access-entry`(IAM ARN ↔ K8s 그룹 매핑) → 그룹에 RBAC 바인딩 (또는 `associate-access-policy`로 AmazonEKSViewPolicy 연결). aws-auth ConfigMap 직접 편집은 구식.

**A8.** **기본이 거부**입니다. 평가기는 허용 규칙들만 검사하고, 어느 규칙에도 매칭되지 않으면 자동으로 Forbidden을 반환합니다.
