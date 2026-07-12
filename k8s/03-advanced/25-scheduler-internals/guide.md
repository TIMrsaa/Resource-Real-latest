# 학습 가이드 — "플러그인 파이프라인"으로 다시 보기

## 모듈 12와의 관계

모듈 12는 사용자 입장(YAML에 뭘 적나), 이 모듈은 구현자 입장(그 YAML을 누가 어느 단계에서 읽나)입니다. 같은 지식의 양면:

| 모듈 12의 손잡이 | 이 모듈의 플러그인 | 단계 |
|------------------|-------------------|------|
| nodeSelector/nodeAffinity | NodeAffinity | Filter+Score |
| taint/toleration | TaintToleration | Filter+Score |
| requests 자원 | NodeResourcesFit | Filter+Score |
| topologySpread | PodTopologySpread | Filter+Score |
| podAffinity | InterPodAffinity | Filter+Score |
| priority/preemption | (PostFilter의 DefaultPreemption) | PostFilter |

"기능 추가 = 플러그인 추가"라는 구조 덕에 스케줄러가 20개 넘는 기능에도 무너지지 않습니다 — 좋은 확장 아키텍처의 표본으로 읽어라.

## 이 모듈에서 얻어야 할 운영 감각

1. **"Pending 메시지를 플러그인 언어로 읽기"**: `0/5 nodes are available: 2 Insufficient cpu, 3 node(s) had untolerated taint...` — 어느 Filter가 몇 노드를 떨어뜨렸는지의 집계입니다. 이게 읽히면 스케줄링 디버깅은 끝난 것.
2. **백오프 큐의 존재**: 스케줄 실패 Pod는 즉시 재시도되지 않습니다(backoff) — "노드 비웠는데 Pending이 몇 초 머무는" 이유.
3. **Karpenter와의 관계**(eks 파트 예고): Karpenter는 스케줄러를 대체하지 않습니다 — **Pending Pod를 보고 노드를 만들어주는** 별개 컨트롤러이고, 배치 자체는 여전히 kube-scheduler가 합니다.
