# 자가 점검 퀴즈

**Q1.** 타임아웃 부등식(앱 keep-alive vs ALB idle)과, 역전 시 생기는 증상·원리는?

**Q2.** 502/503/504를 각각 한 줄로 — 그리고 "ALB가 만든 오류인지 앱이 만든 오류인지"를 가르는 access log의 두 필드는?

**Q3.** `/delay/8` 요청이 idle_timeout=5s에서 어떻게 되나요? 앱 입장과 유저 입장을 나눠 설명하세요.

**Q4.** LOR(least outstanding requests)이 느린 타깃을 자연히 피하게 되는 원리를 Little's Law로 설명하세요.

**Q5.** readiness gate가 없을 때 배포 중 5xx가 나는 메커니즘(입장 쪽)과, gate가 그것을 어떻게 고치는가요?

**Q6.** preStop sleep과 deregistration_delay는 각각 무엇을 기다리는 시간인가요? 하나만 있으면 안 되는 이유는?

**Q7.** NLB cross-zone 기본값과, off 상태에서 생기는 운영 문제 + 두 가지 해법은?

**Q8.** "무중단 배포가 됐는지"를 감이 아니라 증거로 만드는 방법은? (이 모듈의 검증 절차)

---

## 정답

**A1.** 앱 keep-alive > ALB idle(기본 60s)이어야 합니다. 역전되면 ALB가 재사용하려는 백엔드 커넥션을 앱이 먼저 닫아 — 닫힌 커넥션에 요청이 실리는 race → **간헐적 502**. 트래픽 패턴에 따라 드문드문 나서 미스터리처럼 보입니다.

**A2.** 502 = 백엔드가 연결을 끊거나 거부(죽은 Pod 전송, keep-alive race). 503 = healthy 타깃 0개. 504 = idle_timeout 안에 응답 시작 안 됨. 판별: `elb_status_code` vs `target_status_code` — 다르면 ALB 산(産), 같으면 앱 산.

**A3.** 앱: 8초 뒤 정상적으로 200을 만듭니다(자기는 성공했다고 압니다). 유저: 5초 시점에 ALB가 커넥션을 포기하고 **504**를 반환 — 응답은 도착할 곳이 없습니다. 교훈: idle_timeout은 최장 요청 시간보다 길게, 또는 긴 작업은 비동기로.

**A4.** 타깃별 in-flight(outstanding) = 그 타깃의 λ×W. W(지연)가 큰 타깃은 같은 유입에서도 outstanding이 크게 유지되므로, "outstanding 최소" 규칙이 자동으로 그 타깃을 덜 고릅니다 — 지연이 스스로 배정 신호가 됩니다.

**A5.** k8s의 Ready(readinessProbe)와 ALB의 healthy(TG 등록+헬스체크)는 독립 진행 — k8s가 새 Pod를 Ready로 보고 옛 Pod를 죽이는데 ALB 등록이 늦으면 healthy 부족(503/502). gate는 "TG에서 healthy"를 **Pod Ready의 조건으로 주입**해 롤링이 ALB의 준비 속도에 맞춰 진행되게 합니다.

**A6.** preStop sleep = "이 Pod가 빠진다"는 정보(엔드포인트 제거·deregister 시작)가 **전파되는 시간**을 살아서 버티는 것. deregistration_delay = draining 상태에서 **이미 잡힌 요청이 끝나는 시간**. 전자 없이는 전파 전 즉사로 502, 후자 없이는(0초면) 긴 요청이 잘립니다 — 서로 다른 구간을 지키는 세트입니다.

**A7.** 기본 off (ALB는 on). off + AZ별 Pod 수 불균형 = 특정 존 타깃만 과부하(존별 NLB 노드가 자기 존 타깃에만 분배). 해법: ① cross-zone 활성화(AZ 간 전송 과금 여부 확인) ② topologySpreadConstraints로 Pod를 존에 균등 배치.

**A8.** open 모델 부하(vegeta 고정률)를 흘리는 **도중에** 배포하고 Success ratio/상태코드 분포를 기록 — 100%면 증명, 아니면 오류 수가 곧 부채의 크기입니다. 이 측정을 배포 파이프라인의 정기 검증으로 넣습니다(lab-02).
