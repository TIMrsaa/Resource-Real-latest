# Lab 02 — Burst! 메시지 1만 건 주입

> **🌱 핵심 개념 미리보기**
> - **SendMessageBatch**: SQS 의 묶음 송신 API (한 번에 최대 10건). 단건 호출 대비 10배 처리량.
> - **xargs -P**: 병렬 실행. 1만 건을 batch 로 빠르게 보내려면 필수.
> - **NodeClaim 단계**: `Launched → Registered → Initialized → Ready`. 각 단계 타이밍이 노드 cold-start 의 핵심.
> - **Pending → Running**: Karpenter 가 노드 만들고 kubelet join 까지 ~60~90s, 그 후 Pod 스케줄.
> - **cooldown teardown**: 큐가 비어도 즉시 0 안 됨. KEDA cooldown(기본 300s) + Karpenter consolidation(30s 간격).

## 1. 시작 시각 기록

```bash
START=$(date +%s)
echo "Start: $(date) (epoch=$START)"
```

## 2. SQS 에 1만 건 주입 (배치 송신)

SQS SendMessageBatch 는 한 번에 10건. 병렬로 빠르게:

```bash
SEND_BATCH() {
  local START=$1
  local COUNT=10
  ENTRIES=""
  for i in $(seq 0 $((COUNT-1))); do
    ID=$((START + i))
    ENTRIES="${ENTRIES} Id=msg-${ID},MessageBody=\"{\\\"order_id\\\":\\\"o-${ID}\\\",\\\"amount\\\":$((RANDOM%1000))}\""
  done
  aws sqs send-message-batch --queue-url $QUEUE_URL --entries $ENTRIES > /dev/null
}
export -f SEND_BATCH
export QUEUE_URL

# 1000 batch × 10 messages = 10000
seq 1 10000 10 | xargs -P 20 -I{} bash -c 'SEND_BATCH {}'

echo "Sent 10000 messages"
echo "Queue size:"
aws sqs get-queue-attributes --queue-url $QUEUE_URL \
  --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
  --query 'Attributes' --output table
```

> **🧠 `MessagesNotVisible` 의 의미**
> SQS 는 메시지 수신(receive) 시 visibility timeout 동안 다른 컨슈머에게 안 보이게 숨김 → `NotVisible` 카운트로 잡힘.
> 즉 처리 중인 메시지 수 ≈ 활성 Pod 가 잡고 있는 작업량. 비어가는 데도 NotVisible 가 크면 Pod 가 처리 중.
> 만약 NotVisible 이 줄지 않으면 Pod 가 stuck 또는 visibility timeout 이 너무 길음.

## 3. 관찰 시작

준비한 터미널 A/B/C 에서 진행 관찰.

### T+30s ~ T+60s: KEDA 가 Pod 늘리기 시작
**터미널 A**:
```
NAME                              STATUS    NODE
payment-service-xxx-aaa           Pending   <none>
payment-service-xxx-bbb           Pending   <none>
... (30개 모두 Pending)
```

### T+60s ~ T+120s: Karpenter 가 노드 추가
**터미널 B**:
```
NAME              STATUS    INSTANCE-TYPE   ZONE
ip-10-20-x-x...   Ready     m5a.xlarge      ap-northeast-2a    ← 새로!
ip-10-20-y-y...   Ready     m5.xlarge       ap-northeast-2b    ← 새로!
```

```bash
kubectl get nodeclaims
```
→ NodeClaim 진행 단계 (Launched → Registered → Initialized → Ready).

> **🧠 NodeClaim 4단계의 의미**
> | 단계 | 의미 | 누가 |
> |------|------|------|
> | Launched | EC2 RunInstances 호출 성공 (인스턴스 ID 생김) | Karpenter |
> | Registered | EKS 가 노드 인식 (Access Entry 매칭) | EKS API |
> | Initialized | kubelet 이 Ready 보고 + 시스템 Pod 띄움 | kubelet |
> | Ready | 사용자 Pod 스케줄 가능 상태 | scheduler |
>
> Launched → Ready 까지 보통 60~90 초. 어디서 stuck 인지 보면 trouble shooting 의 시작점.

### T+120s ~: Pod 들 Running
**터미널 A**:
```
payment-service-xxx-aaa     Running   ip-10-20-x-x   1/1
payment-service-xxx-bbb     Running   ip-10-20-x-x   1/1
... (30개)
```

### T+120s ~ T+10min: 메시지 처리
**터미널 C**: 큐 길이 감소
```
ApproximateNumberOfMessages
8500
6200
3800
1100
0    ← 처리 완료
```

## 4. 처리 완료 시각 기록

```bash
END_PROCESS=$(date +%s)
DURATION=$((END_PROCESS - START))
echo "Processing completed: $(date)"
echo "Total duration: ${DURATION}s"
```

## 5. 큐 비고 cooldown 시작

```bash
sleep 100
```

**터미널 A**: Pod 0 으로 줄어듦.
**터미널 B**: 빈 노드 발생 → 30초 후 회수.

> **🧠 teardown 도 두 단계**
> ① KEDA cooldown 만료 → Pod 0 으로. ② 빈 노드 발생 → Karpenter Consolidation 이 회수.
> Karpenter 의 Consolidation 은 ~15초 주기로 노드 효율 평가 → 빈 노드 즉시 회수, under-utilized 노드는 합치기 시도.
> 즉 "Pod 0 → 노드 0" 사이 30~60 초 추가 시간이 항상 존재. 비용 청구는 이 시간까지 됨.

```bash
END_TEARDOWN=$(date +%s)
echo "Pods scaled to 0: $(date)"
```

## 6. 끝 — 완전 0 상태 복귀

```bash
sleep 30
kubectl get pods -n order -l app.kubernetes.io/name=payment-service
kubectl get nodes -l managed-by=karpenter
```

기대: Pod 0개, Karpenter 노드 0개 (또는 최소).

```bash
END_FINAL=$(date +%s)
TOTAL=$((END_FINAL - START))
echo "Total time from start to teardown: ${TOTAL}s ($(($TOTAL / 60)) min)"
```

## 7. 핵심 timing 기록

다음 lab 분석을 위해 기록:
| 시점 | 시간 |
|------|------|
| T0 — 메시지 주입 시작 | $(date) |
| T1 — 첫 Pod Running | ? |
| T2 — Karpenter 노드 Ready | ? |
| T3 — 큐 비음 | ${END_PROCESS}s |
| T4 — Pod 0 | ${END_TEARDOWN}s |
| T5 — Node 0 | ${END_FINAL}s |

다음: [lab-03-analysis.md](./lab-03-analysis.md)
