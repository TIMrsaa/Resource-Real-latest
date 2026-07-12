# 자가 점검 퀴즈

**Q1.** `kubectl top pods`의 데이터가 거쳐온 경로를 컴포넌트 순서로 쓰라.

**Q2.** requests cpu=250m인 Pod 2개가 평균 400m씩 쓰고 있고 목표 이용률은 80%입니다. HPA가 계산할 desired replicas는?

**Q3.** CPU 이용률에 160% 같은 100% 초과 값이 가능한 이유는?

**Q4.** 부하가 끝났는데 5분간 replicas가 안 줄어드는 이유와, 그 설계 의도는?

**Q5.** HPA와 VPA를 같은 Deployment에 쓰면 안 되는 조건과 그 이유는?

**Q6.** VPA의 가장 안전한 활용 모드와 그 운영 용도는?

**Q7.** "푸시 알림 직후 초 단위 스파이크"에 HPA가 구조적으로 늦는 이유와 보완책 2가지는?

---

## 정답

**A1.** 컨테이너 cgroup → **kubelet**(cAdvisor) → **metrics-server**(집계, 인메모리) → Metrics API(metrics.k8s.io) → kubectl top / HPA 컨트롤러.

**A2.** 이용률 = 400/250 = 160%. desired = ceil(2 × 160/80) = **4**.

**A3.** 분모가 limits가 아니라 **requests**이기 때문. requests보다 많이 쓰는 것은 (limits 안에서는) 허용되므로 100%를 넘을 수 있습니다.

**A4.** scaleDown `stabilizationWindowSeconds`(기본 300) — 그 시간 창 안의 권고값 중 **최대**를 채택하므로 일시 하락에 반응하지 않습니다. 의도: 트래픽 재상승 시 콜드스타트 연쇄와 출렁임(flapping) 방지.

**A5.** **같은 메트릭(예: CPU)** 을 양쪽이 다룰 때. VPA가 requests를 키우면 이용률%가 떨어져 HPA가 replicas를 줄이고, 다시 이용률이 올라 늘리는 식으로 두 컨트롤러가 서로의 입력을 흔듭니다.

**A6.** `updateMode: "Off"` (권고 전용) — 실측 기반 requests 권고값을 받아 주기적 rightsizing(비용 최적화)에 사용. Pod 재시작 부작용도 없습니다.

**A7.** 메트릭 수집/계산 주기(15s+15s)와 Pod 기동 시간(이미지 풀+probe)이 합쳐져 분 단위 지연이 불가피한 **반응형** 시스템이라서. 보완: ① 예측 시점 선제 증설(KEDA cron/예약) ② 평시 여유 용량(목표 이용률 하향, minReplicas 상향) (+이미지 경량화로 기동 단축).
