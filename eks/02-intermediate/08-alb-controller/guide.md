# 학습 가이드 — "Ingress를 만들면 LB가 생긴다"의 뒷면

## 이 컨트롤러의 정체

AWS Load Balancer Controller = **"K8s 객체(Ingress/Service)를 보고 AWS API를 호출하는 컨트롤러"** — k8s 30에서 만든 operator와 같은 구조입니다:

```
watch: Ingress(class: alb), Service(type: LoadBalancer), TargetGroupBinding
reconcile: ALB/NLB·리스너·규칙·대상그룹을 원하는 상태로 (AWS API 호출)
status: LB의 DNS 이름을 객체 status에 기록
```

즉 우리는 K8s 선언만 만지고, AWS 콘솔의 LB는 "컨트롤러의 출력물"입니다 — 콘솔에서 직접 고치면 reconcile이 되돌립니다(k8s 39의 selfHeal과 같은 원리).

## 핵심 선택 하나: 트래픽이 노드를 거치는가

이 모듈에서 가장 중요한 그림:

```
instance 타겟:  ALB → 노드의 NodePort → kube-proxy(iptables) → Pod (홉 +1, k8s 28의 그 경로)
ip 타겟:        ALB → Pod IP로 직행 (VPC CNI 덕에 Pod IP가 진짜라서 가능! — 07)
```

ip 타겟이 EKS의 정석입니다 — 홉 감소(지연↓), 노드 경유 부작용(SNAT, 불균형) 제거, Fargate(06)에선 유일한 선택지. **07에서 배운 "Pod IP = VPC IP"가 만들어주는 보너스**라는 연결을 놓치지 말 것.

## 비용 감각 미리

ALB는 시간당 + 용량 단위(LCU) 과금 — **Ingress마다 ALB 하나면 청구서가 Ingress 수에 비례**합니다. `group.name`(여러 Ingress → ALB 하나)이 그 처방이고 lab-02에서 실습합니다. lab이 끝나면 cleanup 필수 — LB는 이 파트에서 가장 흔한 "잔존 과금" 품목입니다.

## Gateway API와의 관계 (k8s 06의 후속)

이 컨트롤러는 Gateway API도 지원합니다(별도 모드/CRD). 단 학습 효율상 이 모듈은 ALB Ingress 중심으로 — 개념(클래스, 규칙→실물 매핑)은 Gateway에도 그대로 이식됩니다.
