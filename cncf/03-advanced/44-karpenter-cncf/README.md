# 44 — Karpenter: 노드를 실시간으로 빚는 오토스케일러

> 08에서 HPA(Pod 스케일), 18에서 KEDA(이벤트 Pod 스케일), 43에서 Knative(scale-to-zero)를 배웠습니다. 이들은 모두 **Pod** 수를 늘립니다. 하지만 Pod가 늘면 그 Pod를 얹을 **노드**도 있어야 합니다 — 그것이 노드 오토스케일링이고, Karpenter가 그 진화한 답입니다. 전통적 Cluster Autoscaler가 "미리 정의된 노드그룹을 늘리는" 방식이라면, Karpenter는 **대기 중인 Pod의 요구를 보고 딱 맞는 노드를 실시간으로 프로비저닝**합니다(just-in-time). 원래 AWS가 만들었지만 이제 Kubernetes 프로젝트(멀티클라우드 provider 모델)로 넓어졌습니다 — 그래서 이 모듈은 특정 클라우드가 아니라 **노드 오토스케일링의 원리와 Karpenter의 접근**을 다룹니다. 08의 스케줄링·리소스, 09의 노드 관리가 여기서 "노드를 동적으로 빚는" 관점으로 확장됩니다.

## 학습 목표

1. Pod 스케일(HPA·KEDA·Knative)과 노드 스케일(Cluster Autoscaler·Karpenter)의 층 구분을 압니다
2. Cluster Autoscaler(노드그룹 기반)와 Karpenter(just-in-time)의 차이를 압니다
3. Karpenter의 동작(대기 Pod 관찰 → 딱 맞는 노드 선택 → 프로비저닝 → 통합)을 압니다
4. NodePool·NodeClass로 노드 프로비저닝을 선언하고 빈패킹·통합(consolidation)을 이해합니다
5. 노드 오토스케일링의 함정(중단·PDB·스팟·과도한 churn)과 판단을 압니다

## 선행: 08(스케줄링·리소스·오토스케일 — 필수), 09(노드 관리), 43·18(Pod 스케일 대비) · 도구: kind(개념), kubectl
## 비용: 없음 (kind로 개념 — 실제 노드 프로비저닝은 클라우드 필요하나 원리는 로컬로)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-node-autoscaling-concepts.md](./lab-01-node-autoscaling-concepts.md) — Pod↔노드 스케일, 대기 Pod, 스케줄링
3. [lab-02-karpenter-model-and-judgment.md](./lab-02-karpenter-model-and-judgment.md) — NodePool·통합·판단
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 1.5h
