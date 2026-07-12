# 자가 점검 퀴즈

**Q1.** ClusterConfig 파일이 "한 줄 생성" 대비 주는 것 3가지는?

**Q2.** eksctl 실행이 멈췄거나 실패했습니다 — 1순위 진단처는?

**Q3.** EKS kubeconfig에 비밀이 없는 이유와, 실제 자격증명의 출처는?

**Q4.** get-token이 만드는 토큰의 정체와 수명, 그리고 API 서버의 검증 방법은?

**Q5.** kubectl 인증→인가의 5단계 경로를 쓰라 (k8s 11과 연결).

**Q6.** access entries가 aws-auth ConfigMap을 대체한 이유 2가지는?

**Q7.** "배포 봇은 shop ns에서만 edit" — RBAC 없이 구현하는 명령 골격은?

**Q8.** 동료가 "kubeconfig 줘도 안 돼요"라고 합니다 — 진짜 원인과 올바른 온보딩은?

---

## 정답

**A1.** ① 재현성(DR/복제 — 같은 클러스터를 다시) ② 이력/리뷰(Git에서 변경 추적) ③ 기본값의 명시화(dry-run으로 전체 선언 확인). 인프라의 선언형화 — k8s 10 원칙의 인프라 확장.

**A2.** CloudFormation 콘솔의 해당 스택(eksctl-<이름>-cluster 등) **이벤트 탭** — eksctl은 CFN의 포장이라 실패 사유(IAM 한도, 서브넷 부족 등)가 거기에 원문으로 남습니다.

**A3.** users에 인증서/비밀번호 대신 exec(aws eks get-token)만 있어서 — 자격증명은 AWS CLI의 체계(프로파일/SSO/인스턴스 역할)에서 매번 가져옵니다. kubeconfig는 "어떻게 토큰을 만들지"의 지시서일 뿐.

**A4.** 서명된 STS GetCallerIdentity 요청을 포장한 bearer 토큰(`k8s-aws-v1.`), 수명 ~14분. API 서버는 그 서명을 STS로 확인해 "요청자 = 이 IAM ARN"을 AWS로부터 보증받습니다.

**A5.** ① kubeconfig exec → ② get-token(STS 서명) → ③ API 서버가 STS로 검증(인증: IAM ARN 확정) → ④ access entry가 ARN을 K8s 주체/그룹에 매핑 → ⑤ access policy 또는 RBAC이 인가. 인증=IAM, 인가=K8s — k8s 11의 분업 그대로.

**A6.** ① 안전성: CM 편집 오타 한 번에 전원 잠금되는 구조적 위험 제거(API 객체라 검증되고, 편집 수단이 클러스터 밖) ② 감사/관리: list-access-entries로 "누가 들어오나" 전수 조회, ns 스코프 정책, IaC 친화.

**A7.** `aws eks create-access-entry --principal-arn <봇 역할>` → `aws eks associate-access-policy --policy-arn .../AmazonEKSEditPolicy --access-scope type=namespace,namespaces=shop`.

**A8.** kubeconfig는 받은 사람의 IAM으로 인증을 시도하므로(비밀 없음), 원인은 그 IAM의 access entry 부재. 온보딩: ① 그의 IAM ARN으로 entry 생성+정책 연결(최소 권한) ② 본인이 `aws eks update-kubeconfig` 실행 — 파일 전달은 불필요하고 무의미.
