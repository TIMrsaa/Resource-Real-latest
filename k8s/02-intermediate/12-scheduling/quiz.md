# 자가 점검 퀴즈

**Q1.** nodeAffinity와 taint의 "주체" 차이를 한 문장으로.

**Q2.** GPU 노드를 GPU 워크로드 전용으로 만드는 완전한 공식과, 각 요소가 빠졌을 때의 증상은?

**Q3.** 노드가 NotReady가 된 후 정확히 5분 뒤 Pod가 축출되는 메커니즘을 taint 용어로 설명하세요.

**Q4.** `IgnoredDuringExecution`의 의미는?

**Q5.** replicas 6, AZ 3개에서 "AZ당 최대 1개 차이" 분산을 강제하는 YAML 조각을 쓰라.

**Q6.** DoNotSchedule과 ScheduleAnyway의 트레이드오프는?

**Q7.** 클러스터가 꽉 찼는데 긴급 Pod를 즉시 띄워야 합니다. 어떤 메커니즘이 작동하며 무엇이 희생되는가요?

---

## 정답

**A1.** nodeAffinity는 **Pod가 노드를 고르고**, taint는 **노드가 Pod를 거부합니다** (toleration은 그 거부를 견디는 입장권).

**A2.** ① taint(예: `gpu=true:NoSchedule`) — 빠지면 일반 Pod가 GPU 노드를 차지 ② GPU Pod에 toleration — 빠지면 GPU Pod가 GPU 노드에 못 감 ③ GPU Pod에 nodeAffinity — 빠지면 GPU Pod가 **일반 노드로도** 가버림.

**A3.** Node 컨트롤러가 노드에 `node.kubernetes.io/not-ready:NoExecute` taint를 부여 → 모든 Pod에 기본 포함된 해당 toleration의 `tolerationSeconds: 300`이 만료 → NoExecute 효과로 축출.

**A4.** 조건은 **스케줄링 시점에만** 평가됩니다 — 이미 실행 중인 Pod는 이후 노드 라벨이 바뀌어도 영향(축출)을 받지 않습니다.

**A5.**
```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels: { app: <앱라벨> }
```

**A6.** DoNotSchedule: 분포를 **보장**하지만 용량 부족 시 Pending 발생. ScheduleAnyway: 배치는 보장하지만 분포는 점수 수준의 **최선 노력**. 가용성 요구와 탄력성 요구의 저울질.

**A7.** **Preemption** — 긴급 Pod에 높은 PriorityClass가 있으면 스케줄러가 낮은 priority의 Pod를 축출(Terminating)해 자리를 만듭니다. 희생: 낮은 우선순위 워크로드 (RS가 있다면 자리가 날 때 재생성됩니다).
