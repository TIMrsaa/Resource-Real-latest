# 자가 점검 퀴즈

**Q1.** 표준 진단 루틴 5단계를 순서대로 쓰라.

**Q2.** CrashLoopBackOff에서 `logs`가 아니라 `logs --previous`를 봐야 하는 이유는?

**Q3.** exit code 1 / 137 / 127 — 각각의 의미와 단서의 위치는?

**Q4.** "Pod는 전부 Running인데 Service가 503" — 분기점 명령과 두 갈래 수사는?

**Q5.** "IP로는 되는데 이름으로 안 됨" vs "IP로도 안 됨" — 각각의 수사선은?

**Q6.** Deployment가 3/3이어야 하는데 Pod가 1개뿐이고 Pending도 없습니다. 단서는 어디에 있는가요?

**Q7.** PVC가 Pending인 3가지 경우와, 그중 "정상"인 하나는?

**Q8.** 장애 대응이 "종결"되는 조건은?

---

## 정답

**A1.** ① 증상을 한 문장으로(어느 상태에서 멈췄나) ② 계층 가르기(스케줄 전/기동 중/기동 후/연결) ③ 표준 3종 읽기(describe Events → logs --previous → get -o yaml) ④ 가설을 최소 명령으로 확정 ⑤ 수리 + 재발 방지 장치.

**A2.** `logs`는 방금 재시작한(현재) 컨테이너의 로그 — 아직 안 죽어서 단서가 없을 수 있습니다. 사인은 **죽은 직전 인스턴스**의 마지막 출력에 있고 그게 `--previous`입니다.

**A3.** 1 = 앱이 스스로 종료(원인은 앱 로그에). 137 = 128+9, SIGKILL — 대부분 OOMKilled(앱 로그에 단서 없음, describe의 Last State가 증거). 127 = command not found(스펙의 command/이미지 불일치 — describe/스펙에서).

**A4.** `kubectl get endpoints <svc>`. **비어 있으면** Service 쪽: 셀렉터-라벨 불일치 or 전원 NotReady(readiness). **차 있으면** 경로 쪽: NetworkPolicy, 포트, DNS, 클라이언트.

**A5.** 이름만 안 됨 = DNS 확정 — resolv.conf가 정상이면 CoreDNS(상태/과부하, 모듈 16), 비정상이면 Pod의 dnsPolicy. IP로도 안 됨 = 경로 — NetworkPolicy(최근 생성분부터) → 포트 → (EKS) SG.

**A6.** Pod가 "안 보이는" 것은 스케줄 문제가 아니라 **생성 자체가 거부**된 것 — ReplicaSet의 이벤트(`describe rs`)에 admission 거부 사유(quota 초과, PSA 위반, 정책 웹훅)가 있습니다. Pod 이벤트는 Pod가 존재해야 생깁니다.

**A7.** ① StorageClass 오타/부재 ② **WaitForFirstConsumer 모드에서 아직 소비자 Pod가 없음 — 정상 대기** ③ 용량/한도 문제. describe pvc가 셋을 가릅니다.

**A8.** 복구 + 원인 규명 + **재발 방지 장치**(알림/probe/admission/runbook 갱신)까지. "다음에 같은 일이 나면 시스템이 사람보다 먼저 아는가"에 yes가 되어야 종결.
