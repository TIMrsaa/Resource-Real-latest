# 16. Troubleshooting — 7개 장애 시나리오

## 학습 목표

장애를 **인위적으로 재현** 하고 **체계적으로 진단** 하는 능력을 기른다. 각 시나리오에서:
1. 증상 관찰
2. 정보 수집 (kubectl describe, logs, events)
3. 원인 가설
4. 검증 / 해결

## 시나리오 목록

| # | 시나리오 | 핵심 진단 도구 |
|---|----------|---------------|
| 1 | [CrashLoopBackOff](./scenario-1-crashloop.md) | logs, exit code |
| 2 | [ImagePullBackOff](./scenario-2-imagepull.md) | describe events, ECR auth |
| 3 | [Pending Pod](./scenario-3-pending.md) | describe, scheduling, requests |
| 4 | [OOMKilled](./scenario-4-oom.md) | last state, metrics |
| 5 | [Service 호출 무응답](./scenario-5-service.md) | endpoints, DNS |
| 6 | [노드 NotReady](./scenario-6-node.md) | kubelet, system Pod |
| 7 | [PVC stuck Pending](./scenario-7-pvc.md) | CSI Driver, AZ |

## 진행 방법

각 시나리오는 다음 구조:
- **재현** — 의도적으로 망가뜨림
- **증상** — 실제 어떻게 보이는지
- **진단 절차** — 일관된 순서로
- **해결** — 정상화

## 추천 도구

- `kubectl describe pod/node` — events 가 1순위
- `kubectl logs <pod> --previous` — 직전 인스턴스 로그
- `stern` — 다중 Pod 로그 동시
- `k9s` — TUI 로 한 화면에서 다수 보기
- `kubectl events` (1.30+) — 향상된 events 뷰

## 다음 모듈

→ [17-cost-optimization](../17-cost-optimization/)
