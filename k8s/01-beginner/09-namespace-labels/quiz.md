# 자가 점검 퀴즈

**Q1.** Namespace가 격리하는 것 3가지와 격리하지 않는 것 중 가장 위험한 것 1가지는?

**Q2.** dev ns의 Pod가 staging ns의 `web` Service를 호출하는 DNS 주소는?

**Q3.** "env가 prod가 아니고 tier 키가 존재하는 Pod"를 한 명령으로 조회하세요.

**Q4.** Label과 Annotation의 선택 기준을 한 문장으로.

**Q5.** ResourceQuota가 걸린 ns에서 requests 없는 Pod가 거부됩니다. 해결책 2가지는?

**Q6.** Quota 초과로 RS가 Pod를 못 만들고 있습니다. 쿼터를 늘리면 수동 조치가 필요한가?

**Q7.** ns 삭제가 Terminating에서 멈췄습니다. 우선 확인할 것은?

---

## 정답

**A1.** 격리: 이름 범위, RBAC 권한 경계, ResourceQuota 적용 범위. 가장 위험한 비격리: **네트워크** (기본 전부 허용).

**A2.** `web.staging.svc.cluster.local` (또는 줄여서 `web.staging`).

**A3.** `kubectl get pods -l 'env notin (prod),tier'`

**A4.** **셀렉터로 선택할 일이 있으면 Label, 사람/도구가 읽을 메모면 Annotation.**

**A5.** ① LimitRange로 defaultRequest 주입 ② Pod/Deployment에 requests 명시. (근본적으로는 모든 워크로드에 requests를 적는 문화)

**A6.** 불필요 — RS 컨트롤러의 조정 루프가 재시도를 계속하므로 쿼터가 풀리는 즉시 자동으로 채워집니다.

**A7.** 안에 남아 있는 리소스와 finalizer: `kubectl get all,pvc -n X`, `kubectl get ns X -o jsonpath='{.status.conditions}'` — 응답 없는 웹훅이나 finalizer를 가진 리소스가 범인인 경우가 대부분.
