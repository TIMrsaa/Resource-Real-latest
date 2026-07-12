# 자가 점검 퀴즈

**Q1.** 심층 방어 6관문을 나열하고, 각 관문의 k8s 부품과 AWS 층을 하나씩 짝지어라.

**Q2.** "k8s Secret은 암호화되어 있다"가 왜 틀렸는가요? etcd KMS 암호화가 지키는 범위는 정확히 무엇인가요?

**Q3.** Secrets Manager CSI의 구조(3부품)와, 외부화가 주는 이점 3가지는?

**Q4.** CSI의 자동 회전이 "앱에 따라 무의미할 수 있는" 이유는?

**Q5.** IMDS 경로 침해의 단계와 3중 차단, 그중 근본 수단은?

**Q6.** GuardDuty EKS Protection의 두 눈과, "탐지는 방어가 아니다"의 실무적 의미는?

**Q7.** 감사 로그의 보안 감시 쿼리 3종을 들고 각각이 잡는 사건을 설명하세요.

**Q8.** lab-02에서 각 관문이 막은 공격 단계를 순서대로 매핑하세요 — 그리고 "층의 가정이 깨지는" 예를 하나 들라.

---

## 정답

**A1.** ① 공급망: admission 이미지 정책(23) ↔ ECR 스캔·서명. ② 신원: RBAC/SA(11) ↔ IRSA·Pod Identity 최소권한(09). ③ 워크로드: PSA/PSS(32) ↔ Bottlerocket. ④ 네트워크: NetworkPolicy(15·18) ↔ SG·프라이빗 엔드포인트. ⑤ 시크릿: Secret(약점) ↔ Secrets Manager CSI·KMS. ⑥ 탐지: 감사 로그(21) ↔ GuardDuty·CloudTrail.

**A2.** 기본 저장은 base64 **인코딩**(암호화 아님)이며, KMS 봉투암호화를 켜도 그것은 **etcd에 저장된 데이터(디스크·백업 유출)** 만 지킵니다 — API로 `get secrets` 권한이 있는 주체에게는 여전히 평문으로 반환됩니다. 따라서 RBAC 최소화와 외부화가 함께 필요합니다.

**A3.** 부품: SecretProviderClass(CRD — 무엇을 어떻게), secrets-store CSI driver + AWS provider(DaemonSet), SA에 붙은 IRSA/Pod Identity 권한. 이점: ① 원본이 클러스터 밖(etcd·백업 유출에 무관) ② tmpfs 마운트라 디스크에 안 남음 ③ 자동 회전 + CloudTrail 접근 감사 + 자원 ARN 단위 권한.

**A4.** CSI는 **마운트된 파일**을 갱신할 뿐입니다 — 앱이 시작 시 한 번만 읽고 메모리에 들고 있으면 새 값이 반영되지 않습니다. 회전을 살리려면 앱이 파일을 주기적으로 다시 읽거나(권장), 회전 시 롤링 재시작을 트리거해야 합니다.

**A5.** 단계: Pod RCE → `169.254.169.254`로 노드 IAM 자격증명 획득 → 그 역할의 권한만큼 AWS 계정 장악. 3중 차단: ① **hop limit=1**(컨테이너는 1홉 더 멀어 도달 불가 — 근본) ② IMDSv2 토큰 강제(단순 SSRF 차단) ③ 노드 역할 최소화 + 워크로드는 IRSA(훔쳐도 별게 없게).

**A6.** ① Audit Log Monitoring(CP 감사 로그 기반 — 익명 접근, 권한 상승, exec 남용 등) ② Runtime Monitoring(노드의 eBPF 에이전트 — 컨테이너 탈출, 채굴, C2 통신). 의미: Finding이 EventBridge→자동 격리/온콜로 연결되지 않으면, 탐지는 새벽에 아무도 안 보는 알림일 뿐 — 대응 자동화까지가 한 세트.

**A7.** ① `user.username = system:anonymous` 성공 요청 — 익명 접근 허용 사고. ② `objectRef.subresource = exec` — 누가 어느 Pod에 들어갔나(내부자·침해 후 행동). ③ clusterrolebindings의 create/update — 권한 상승의 발자국(11의 escalation).

**A8.** Step 5 VAP(①공급망: 악성 이미지 차단) → Step 2 PSA(③워크로드: privileged/hostPID 탈출 차단) → Step 3 NetworkPolicy(④네트워크: 측면 이동 차단) → Step 4 hop limit(②신원: 노드 역할 탈취 차단) → Step 6 감사·GuardDuty(⑥탐지). 가정이 깨지는 예: hostNetwork Pod가 허용되면 NetworkPolicy를 우회당합니다(④의 전제 붕괴) — 그래서 ③(PSA restricted)이 ④를 지탱합니다.
