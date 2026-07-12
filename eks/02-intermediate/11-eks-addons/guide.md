# 학습 가이드 — "누가 이 컴포넌트의 주인인가"

## 이 모듈이 풀어주는 미스터리

07에서 경고했던 그 현상 — "kubectl set env로 aws-node를 고쳤는데 어느 날 원복돼 있다" — 의 원리가 여기 있습니다. 관리형 애드온은 **EKS가 reconcile하는 객체**입니다: 진실은 애드온 설정(EKS API)에 있고, 클러스터 안의 DaemonSet/Deployment는 그 출력물입니다. k8s 39(GitOps)의 selfHeal과 정확히 같은 구조 — 주인이 ArgoCD가 아니라 EKS일 뿐.

```
주인 정리:
관리형 애드온       EKS가 reconcile      변경은 configuration-values로
Helm 자가 설치     Helm/GitOps가        변경은 values로 (k8s 17)
kubectl 직접      아무도 안 지킴        드리프트 — 금지 (k8s 10)
```

## 왜 "버전"이 모듈 하나인가

클러스터 업그레이드(k8s 35, eks 21)의 사고 절반이 애드온에서 납니다:

- CP는 1.37인데 vpc-cni가 구버전 → 미묘한 비호환
- 애드온을 latest로 올렸는데 그 버전이 현 CP 미지원 → CrashLoop
- 노드만 갈았는데 kube-proxy 애드온 버전이 노드와 어긋남 (k8s 35의 skew!)

"부품마다 호환 매트릭스가 있고, 그걸 API로 조회해 계획한다" — 이 루틴이 모듈의 절반입니다.

## 자가 관리와의 선택 기준 미리

| | 관리형 애드온 | Helm 자가 설치 |
|---|--------------|---------------|
| 버전 호환 검증 | AWS가 (describe-versions) | 내가 |
| 설정 자유도 | 스키마 범위 내 | 무제한 |
| 업그레이드 | API 한 줄 | 차트 업그레이드 절차 |
| 어울림 | 핵심 부품(CNI/CSI/DNS/proxy) | 그 외 전부 (LB 컨트롤러도 가능하지만 애드온 버전도 존재) |

원칙: **핵심 4종(vpc-cni, coredns, kube-proxy, +csi)은 관리형으로** — 클러스터 업그레이드와 보조를 맞추는 비용을 AWS에 위임.
