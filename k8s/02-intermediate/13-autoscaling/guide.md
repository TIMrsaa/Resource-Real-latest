# 학습 가이드 — 오토스케일링은 "3층 건물"입니다

## 전체 지도 (혼동 방지)

스케일링이라는 단어가 3개 층에서 따로 놉니다. 층을 구분하면 도구가 정리됩니다:

```
┌─ 3층: 노드 수      — Cluster Autoscaler / Karpenter (eks 파트 17)
├─ 2층: Pod 개수     — HPA (수평) / KEDA (이벤트 기반, cncf 파트 18)   ← 이 모듈
└─ 1층: Pod 크기     — VPA (수직: requests/limits 조정)               ← 이 모듈
```

2층(HPA)이 Pod를 늘렸는데 노드가 부족하면 Pending → 3층(Karpenter)이 노드를 늘립니다 — 층간 연동이 실전 오토스케일링입니다 (참고폴더의 "Karpenter+KEDA 콤보" 시나리오가 정확히 이것).

## HPA 핵심 한 줄

> **desired = ceil(current × 현재값 / 목표값)** — "이용률이 목표의 2배면 Pod도 2배".

이 식 하나에서 모든 동작이 유도됩니다. lab-01에서 실제 숫자로 검증하니, 식을 먼저 외워두고 가라.

## 자주 깨지는 전제 2개

1. **requests가 없으면 HPA는 죽습니다** — "이용률 %"의 분모가 requests입니다. 분모가 없으니 계산 불가 (`<unknown>`).
2. **YAML의 replicas와 HPA는 싸웁니다** — 모듈 04 pitfall의 재림. HPA 쓰는 워크로드는 YAML에서 replicas를 지워라.

## CPU 말고 다른 기준은?

- 메모리: 가능하지만 보통 나쁜 신호(메모리는 부하에 비례해 줄지 않음)
- **RPS/큐 길이** 같은 비즈니스 메트릭: custom/external metrics — 구조만 이 모듈에서 보고, 실전 구현(Prometheus Adapter/KEDA)은 eks 파트 15에서. "RPS 기반 HPA"가 여러분이 요구한 그 주제입니다.
