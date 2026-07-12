# Lab 01 — 시나리오 셋업

> **🌱 핵심 개념 미리보기**
> - **이중 스케일링 협업**: KEDA = Pod 수 (이벤트 기반), Karpenter = 노드 수 (Pod 의 Pending 신호 기반).
> - **Pending Pod = 트리거**: KEDA 가 Pod 늘리면 노드 자원 부족 → Pending → Karpenter 가 감지해 노드 추가.
> - **0 → N → 0**: 평소 비용 0, 이벤트 시 폭발, 끝나면 0 으로 자동 복귀가 목표.
> - **timing 측정**: KEDA 응답(~30s) → Karpenter 노드(~60~90s) → Pod Running(~120s).
> - **watch 3중창**: Pod / 노드 / 큐 3 개를 동시에 봐야 흐름 이해 가능.

## 1. 사전 점검

```bash
# Karpenter
kubectl get nodepool

# KEDA
kubectl get pods -n keda
kubectl get scaledobject -n order

# payment-service IRSA
kubectl get sa -n order payment-service -o yaml | yq '.metadata.annotations'

# SQS 큐
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
QUEUE_URL=$(aws sqs get-queue-url --queue-name eks-study-payments --query QueueUrl --output text)
echo $QUEUE_URL
```

## 2. payment-service 의 리소스 명확화

```bash
sed "s|ACCOUNT_ID|${ACCOUNT_ID}|g; s|SQS_URL|${QUEUE_URL}|g" \
  manifests/payment-with-resources.yaml | kubectl apply -f -
```

(이미 모듈 13 에서 비슷한 spec 으로 떠 있을 가능성. 위 명령은 update.)

> **🧠 resources.requests 가 Karpenter 핵심 입력**
> Karpenter 의 노드 sizing 결정은 **Pod 의 requests 합산** 에 100% 의존. limit 은 무시.
> requests 가 너무 크면 → 큰 노드 띄우고 비효율. 너무 작으면 → 한 노드에 과밀 → 실제 OOM.
> 이 lab 에선 payment 의 requests 를 명시 (예: 100m CPU, 128Mi) 해야 노드 수 계산이 정확.

## 3. ScaledObject 가 큐 모니터링 중 확인

```bash
kubectl describe scaledobject -n order payment-service
```

기대: `Active: True` (또는 큐 비어있으면 False — 정상).

> **🧠 ScaledObject `Active` 컨디션의 의미**
> `Active=True`: trigger 가 임계값 이상 → KEDA 가 HPA 활성화 → minReplicaCount 이상 유지.
> `Active=False`: trigger 가 임계값 미만 → cooldown 후 0 으로. 정상 idle 상태.
> 만약 `Ready=False` 가 보이면 IRSA/권한 문제. `kubectl describe scaledobject` 의 events 확인 필요.

## 4. 노드 / Pod 베이스라인 캡처

```bash
echo "=== Baseline @ $(date) ==="
echo "Pods:"
kubectl get pods -n order -l app.kubernetes.io/name=payment-service
echo "Nodes (Karpenter):"
kubectl get nodes -l managed-by=karpenter -o wide
```

기대: payment-service Pod 0 개, Karpenter 노드 0 또는 최소.

## 5. Watch 터미널 준비 (3개)

**터미널 A — Pod**:
```bash
watch -n2 'kubectl get pods -n order -l app.kubernetes.io/name=payment-service -o wide'
```

**터미널 B — 노드**:
```bash
watch -n2 'kubectl get nodes -l managed-by=karpenter -L node.kubernetes.io/instance-type,topology.kubernetes.io/zone'
```

> **🧠 watch 가 3 개나 필요한 이유**
> KEDA 와 Karpenter 는 비동기 컨트롤 루프 → 한 화면에 모두 안 보임. Pod (KEDA 결과) / 노드 (Karpenter 결과) / 큐 (원인 지표) 를 분리해 봐야 흐름이 명확.
> 시간차도 핵심: 큐가 차고 → ~30 초 후 Pod Pending → ~60 초 후 노드 Ready → ~120 초 후 Pod Running. 각 단계가 보임.

**터미널 C — 큐 길이**:
```bash
watch -n5 "aws sqs get-queue-attributes --queue-url $QUEUE_URL \
  --attribute-names ApproximateNumberOfMessages \
  --query 'Attributes.ApproximateNumberOfMessages' --output text"
```

## 6. (선택) Grafana 열기

```bash
kubectl port-forward -n monitoring svc/kps-grafana 3000:80 &
```

→ http://localhost:3000 → Dashboards → "Kubernetes / Compute Resources / Namespace (Pods)" → namespace=order.

준비 완료. 다음: [lab-02-burst.md](./lab-02-burst.md)
