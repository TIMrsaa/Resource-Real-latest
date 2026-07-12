# 자가 점검 퀴즈

**Q1.** 관측성 3축이 각각 답하는 질문과, k8s 38의 진단 루틴과의 관계는?

**Q2.** amazon-cloudwatch-observability 애드온이 클러스터에 만드는 구성요소를 구조로 그려라.

**Q3.** 컨테이너의 stdout 한 줄이 CloudWatch에 닿는 경로를 단계별로. 앱이 파일이 아닌 stdout에 로그를 쓰는 이유도.

**Q4.** "로그는 오는데 ContainerInsights 메트릭이 안 보인다" — 이 증상의 진단 경로와 그 근거가 되는 구조는?

**Q5.** 로그 수집이 DaemonSet인 이유는? (k8s 13의 용어로)

**Q6.** CloudWatch Logs 비용의 두 함정(수집/보존)과 각각의 통제 수단은?

**Q7.** Pod 하나만 로그 수집에서 빼는 방법과, 더 큰 범위 통제의 통로는?

**Q8.** "IncomingBytes에 알람을 건다"의 의미를 한 문장으로 — 왜 이것이 중급 졸업 체크리스트에 있나요?

---

## 정답

**A1.** 메트릭 = "이상한가/얼마나/언제부터"(시계열, 알람의 재료), 로그 = "왜"(서술), 트레이스 = "여러 서비스 중 어디서"(요청 경로). 38의 describe/logs는 장애 **후** 클러스터에 묻는 것 — 관측성은 같은 답을 **미리, 클러스터 밖에**(Pod/노드가 죽어도 남게) 적어둡니다.

**A2.** EKS Addon → Operator(Deployment) → ① cloudwatch-agent DaemonSet(메트릭→EMF→/performance) ② fluent-bit DaemonSet(로그→/application 등). 로그 그룹 4형제: application/dataplane/host/performance.

**A3.** stdout → containerd가 `/var/log/containers/*.log`로 → 그 노드의 Fluent Bit이 tail + kubernetes 필터로 ns/pod/라벨 메타데이터 주입 → CloudWatch Logs(/application). 파이프라인이 stdout만 줍기 때문에 — 파일에 쓰면 이 길에 안 올라탑니다(12-factor의 근거).

**A4.** 메트릭은 EMF 로그(/performance)를 경유해 생성되므로: /performance에 EMF JSON이 오는지 먼저 → 오면 콘솔 리전/메트릭 네임스페이스 문제 → 안 오면 cloudwatch-agent DS 헬스/권한 문제. "메트릭도 사실은 로그"라는 구조가 진단 순서를 정해줍니다.

**A5.** 로그 파일이 **노드마다** 있으므로(`/var/log/containers`) 수집기도 노드마다 정확히 1개 필요 — "모든 노드에 하나씩"이 DaemonSet의 정의입니다.

**A6.** ① 수집: GB당 과금이 저장보다 비쌈 — debug 방치가 폭탄. 통제: 수집 필터(exclude/레벨 규약) + IncomingBytes 알람. ② 보존: 기본 **무기한** — 유령 저장 비용. 통제: 로그 그룹마다 put-retention-policy(7~30일).

**A7.** Pod(템플릿)에 annotation `fluentbit.io/exclude: "true"` — Fluent Bit kubernetes 필터가 그 Pod 로그를 버립니다. 더 큰 범위는 애드온 configuration-values(11의 단일 통로)로 수집 구성 자체를 조정.

**A8.** "관측성 스택 자체를 관측한다" — 수집량 급증(=비용 사고이자 어딘가 이상 신호)을 사람이 청구서로 알기 전에 기계가 알리는 장치. 관측성이 새 비용 축을 만들었으니 그 축에도 계기판이 필요합니다.
