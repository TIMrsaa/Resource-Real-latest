# 학습 가이드 — 노드가 다 같다는 가정이 깨지는 날

## 왜 지금 이기종인가

13~18의 최적화(측정, LB, 스케일, IP, 노드, 패킷)는 전부 "노드는 amd64 EC2"라는 가정 위였습니다. 그 가정을 깨는 압력이 두 방향에서 옵니다:

1. **재무의 압력**: 같은 성능을 더 싸게 — Graviton(arm64)은 대개 20~40% 낮은 단가. 클러스터 절반만 옮겨도 노드 비용이 눈에 띄게 줍니다 (22 비용 모듈의 주력 카드 중 하나)
2. **워크로드의 압력**: ML 추론/학습, 트랜스코딩 — CPU로는 안 되는 일. GPU(NVIDIA)나 Neuron(AWS 자체 칩)이 필요합니다

## 이 모듈의 렌즈: 스케줄링 어휘

이기종의 기술적 본질은 새 하드웨어가 아니라 **스케줄러에게 차이를 가르치는 것**입니다 — 이미 배운 어휘로 전부 표현됩니다:

| 차이 | 어휘 | 배운 곳 |
|------|------|---------|
| "이 노드는 arm이다" | label `kubernetes.io/arch` + nodeSelector | k8s 12 |
| "GPU 워크로드만 와라" | taint/toleration | k8s 12, 34 |
| "이 노드엔 GPU가 2장" | **extended resource** (`nvidia.com/gpu: 2`) — device plugin이 등록 | 이 모듈의 신입 |
| "arm 노드도 만들어라" | Karpenter requirements에 arm64 추가 | 17 |

extended resource 하나만 새 개념입니다 — kubelet에게 "CPU/메모리 말고 이런 자원도 있다"고 플러그인이 신고하면, 스케줄러는 그것을 requests/limits처럼 계산합니다.

## 순서에 대한 변명

Graviton을 먼저 하는 이유: 싸고(t4g), 위험이 낮고, **아키텍처 불일치라는 이기종의 근본 문제**(exec format error)를 GPU보다 깨끗하게 보여줍니다. GPU는 그 문법 위에 "장비 등록"이 얹힌 것 — lab-02는 비용 때문에 선택 실습으로 설계했지만, 이론과 manifest는 완주합니다.
