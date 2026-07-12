# 자가 점검 퀴즈

**Q1.** EKS 장애의 4계층과 각 계층의 "CCTV"(증거가 남는 곳)를 매핑하세요.

**Q2.** 심문 순서가 "앱 → k8s → EKS → AWS"인 이유 두 가지는? 그보다 빠른 질문은?

**Q3.** Pending과 ContainerCreating을 계층으로 구분하고, 각각의 대표 원인·확진 명령을 들라.

**Q4.** "IP 고갈에 노드를 추가"가 왜 상황을 악화시키는가요?

**Q5.** Pod에서 AWS 호출이 실패할 때, 정책을 뒤지기 전에 확인해야 할 것은? 이유는?

**Q6.** 앱 로그에 오류가 없고 `get endpoints`도 정상인데 유저가 502를 봅니다 — 계층 판정과 확진 필드, 두 가지 원인 분기는?

**Q7.** 장애 대응의 첫 명령이 진단이 아니라 수집이어야 하는 이유는?

**Q8.** "Flow Logs ACCEPT"와 "endpoints 정상"이 무죄 증명이 아닌 이유를 각각 설명하세요.

---

## 정답

**A1.** ④ 앱 — 앱 로그(12의 파이프라인)·앱 메트릭. ③ k8s 오브젝트 — describe/events(**~1시간 후 소멸**)·컨트롤러 로그. ② EKS 관리면 — 감사 로그(21)·insights·describe-addon health.issues. ① AWS 인프라 — CloudTrail·VPC Flow Logs·ipamd 로그·Health Dashboard.

**A2.** ① 확인 비용이 쌉니다(kubectl 한 줄 vs 네트워크팀 소환) ② 확률이 높습니다(자주 바뀌는 곳이 자주 고장납니다). 그보다 빠른 질문: **"어제까지 됐나요? 뭘 바꿨나요?"** — 원인의 대다수는 최근 변경(배포·애드온·정책·노드)입니다.

**A3.** Pending = 스케줄러가 자리를 못 찾음(k8s 계층 ③) — 자원 부족·taint·affinity·NodePool limits. 확진: `describe pod`의 이벤트(`Insufficient cpu`)·Karpenter 로그. ContainerCreating = 자리는 찾았는데 kubelet/CNI가 준비 실패(①/③ 경계) — IP 고갈·이미지 pull·볼륨 attach. 확진: 이벤트(`failed to assign an IP address`)·`describe-subnets`.

**A4.** 새 노드마다 ipamd가 warm pool로 **또 수십 개의 IP를 선점**하므로(07·16), 부족한 서브넷의 잔여 IP가 더 빨리 마릅니다. 처방은 증설이 아니라 warm 회수·prefix delegation·secondary CIDR, 또는 여유 AZ로의 유도.

**A5.** **자격증명 배선의 존재 여부** — `kubectl exec ... env | grep AWS_`로 역할 ARN·토큰 경로 주입 흔적, 그리고 association 존재 확인. 이유: 주입 자체가 없으면(SA 오타, association 누락, SA 생성 후 Pod 미재시작) 정책은 아무 관계가 없습니다. **존재 확인이 내용 확인보다 먼저**.

**A6.** 계층: ALB↔Pod 경계(②/①) — 앱은 알리바이가 있습니다. 확진 필드: ALB access log의 `elb_status_code` vs `target_status_code`(다르면 ALB가 만든 오류). 분기: 502가 **배포 시각에 몰리면** draining 중 전송(preStop·readiness gate 부재), **산발적이면** keep-alive 역전(앱 < ALB idle 60s).

**A7.** 조치(재시작·재배포·Pod 삭제)는 증상과 함께 **증거를 지웁니다** — 이벤트는 ~1시간 후 소멸하고, 삭제된 Pod의 `--previous` 로그는 복구 불가. 수집 스크립트를 30초 돌린 뒤 조치하면 서비스도 살리고 사후 분석도 삽니다.

**A8.** Flow Logs ACCEPT: ENI 관문을 통과했다는 기록일 뿐 — NetworkPolicy의 eBPF 드롭은 그 뒤에서 일어나 찍히지 않습니다(18). endpoints 정상: k8s가 Pod를 Ready로 본다는 뜻일 뿐 — ALB가 그 타깃을 등록·healthy 판정했는지는 별개(14의 readiness gate가 필요한 이유). 둘 다 "그 계층까지는 통과"라는 진술이지 무죄 증명이 아닙니다.
