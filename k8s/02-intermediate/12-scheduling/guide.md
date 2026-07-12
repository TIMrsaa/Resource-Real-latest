# 학습 가이드 — 방향만 잡으면 절반입니다

## 기능이 5개나 되는 이유

전부 다른 질문에 답합니다:

| 질문 | 기능 |
|------|------|
| "이 Pod는 **어떤 노드**에?" | nodeSelector / nodeAffinity |
| "이 **노드**는 아무나 못 와" | taint + toleration |
| "이 Pod는 **저 Pod와** 같이/떨어져" | podAffinity / podAntiAffinity |
| "복제본들을 **고르게 퍼뜨려**" | topologySpreadConstraints |
| "자리 없으면 **누굴 쫓아내서라도**" | PriorityClass + preemption |

## 가장 헷갈리는 것: taint의 방향

- nodeSelector/affinity = **Pod가 노드를 고릅니다** ("난 GPU 노드 갈래")
- taint = **노드가 Pod를 밀어냅니다** ("출입금지 표지판") / toleration = "난 그 표지판 견딜 수 있어"

핵심 비대칭: **toleration은 입장권이지 지정석이 아닙니다.** GPU 노드에 taint를 걸고 GPU Pod에 toleration만 주면, 그 Pod는 일반 노드에도 갈 수 있습니다. "GPU Pod는 GPU 노드에**만**" = toleration(입장 허용) + nodeAffinity(거기로 가라) **둘 다** 필요. 이 조합이 시험과 실무 단골.

## 실무에서 제일 중요한 것 하나만 꼽으면

**topologySpreadConstraints로 AZ 분산.** replicas 3개가 우연히 한 AZ에 몰려 있으면 AZ 장애 = 전멸입니다. EKS 노드에는 `topology.kubernetes.io/zone` 라벨이 이미 있습니다 — lab-02에서 직접 분산을 검증합니다. (Karpenter/Spot 환경에서는 더더욱 — eks 파트 17)

## required vs preferred

affinity류에는 두 강도가 있습니다: `required...`(못 맞추면 Pending) / `preferred...`(맞추면 좋고 아니면 말고). **required는 Pending 사고의 단골 원인** — 웬만하면 preferred + 점수로 시작하고, 보안/라이선스처럼 진짜 불변 조건만 required로.
