# 퀴즈 — 04. RBAC & Helm

### Q1. ServiceAccount 가 명시되지 않은 Pod는 어떤 SA로 인증하는가?

A. SA 없음
B. 동일 NS의 `default` SA
C. `kube-system/default` SA
D. 클러스터의 `cluster-admin`

---

### Q2. RoleBinding이 ClusterRole 을 참조하는 효과는?

A. 그 NS 안에서 ClusterRole의 권한을 사용 (재사용 패턴)
B. 클러스터 전역에 적용
C. 에러
D. 무시됨

---

### Q3. `kubectl auth can-i list pods --as=system:serviceaccount:dev:my-sa` 는 무엇을 점검하는가?

---

### Q4. EKS에서 IAM 사용자가 K8s API에 접근하려면 추가로 필요한 단계는?

A. 자동 인증
B. `aws-auth` ConfigMap 또는 EKS Access Entries 설정
C. IAM 정책만 추가
D. ServiceAccount 만들기

---

### Q5. Helm `--set` 과 `-f values.yaml` 중 우선순위가 높은 것은?

A. `-f`
B. `--set`
C. 동일
D. 차트 기본값(values.yaml in chart)이 항상 우선

---

### Q6. `helm template` 과 `helm install --dry-run --debug` 의 차이는?

---

### Q7. `helm rollback my-app 1` 은 어떤 동작을 하는가?

A. revision 1을 활성화하고 새 revision(예: 5)을 만든다
B. revision 1로 완전히 되돌리고 그 이후 이력은 삭제
C. revision 1만 보여준다 (read-only)
D. revision 1을 삭제한다

---

### Q8. Chart의 `_helpers.tpl` 의 역할은?

---

### Q9. HPA가 scale down 보다 scale up을 빠르게 하는 이유는?

---

### Q10. (실습 검증) order-service Helm 차트를 dev / prod 두 환경에 다른 replicas/이미지로 배포하려면 어떤 구조로 values 파일을 가져갈까? 한 줄로 설명.

---

## 정답

<details>

**Q1**: B
**Q2**: A — Role 정의를 매번 만들지 않고 ClusterRole을 NS별로 재사용하는 흔한 패턴
**Q3**: `dev` NS의 `my-sa` ServiceAccount 가 Pod 목록 조회 권한이 있는지 점검
**Q4**: B
**Q5**: B — `--set` 이 가장 우선
**Q6**: `helm template` 은 클라이언트 측 렌더만 (서버 호출 없음). `--dry-run --debug` 는 서버에 요청해 admission/검증까지 포함된 시뮬레이션.
**Q7**: A — 이전 revision의 매니페스트 내용을 새 revision으로 적용 (이력 보존)
**Q8**: 차트 전체에서 재사용할 함수/이름 정의 (예: `fullname`, `labels`)를 한 곳에 모아두는 곳
**Q9**: 부하 폭주 시 빠른 대응 필요 / 일시적 변동에 너무 민감하게 줄이면 다시 늘려야 하는 비효율 → 기본 stabilization window 5분
**Q10**: `values.yaml` (공통 기본) + `values-dev.yaml` + `values-prod.yaml` (각 환경 오버라이드) → `helm install ... -f values.yaml -f values-prod.yaml`

</details>

다음: [pitfalls.md](./pitfalls.md)
