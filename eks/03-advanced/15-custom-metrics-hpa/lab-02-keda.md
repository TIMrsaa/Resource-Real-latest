# Lab 02 — KEDA: 같은 목표, 다른 손잡이 — 그리고 0의 함정

lab-01의 부품 조립을 KEDA는 CRD 한 장으로 접습니다. 같은 스케일링을 재현한 뒤, KEDA만의 능력(scale-to-zero)과 그 함정을 정면으로 봅니다.

전제: lab-01의 scalelab(podinfo)과 monitoring(Prometheus) 유지, HPA는 삭제된 상태.

## Step 1. KEDA 설치

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm install keda kedacore/keda -n keda --create-namespace
kubectl get pods -n keda    # operator + metrics-apiserver + admission webhooks
kubectl get apiservice v1beta1.external.metrics.k8s.io -o wide   # KEDA가 external 창을 서빙
```

✅ lab-01의 Adapter는 **custom** 창, KEDA는 **external** 창 — API 그룹이 달라 공존 가능. (단 같은 Deployment를 둘이 조종하게 하면 안 됩니다 — 그래서 lab-01 HPA를 지웠습니다.)

## Step 2. ScaledObject — 어댑터 규칙+HPA를 한 장으로

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata: { name: podinfo, namespace: scalelab }
spec:
  scaleTargetRef: { name: podinfo }
  minReplicaCount: 2
  maxReplicaCount: 8
  cooldownPeriod: 120
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus-server.monitoring.svc
      query: sum(rate(http_request_duration_seconds_count{namespace="scalelab"}[1m]))
      threshold: "50"            # replica당 목표 — lab-01의 averageValue와 같은 의미
EOF

kubectl get scaledobject -n scalelab       # READY: True
kubectl get hpa -n scalelab                # keda-hpa-podinfo — KEDA가 만든 HPA!
```

✅ theory §4의 실증: KEDA는 HPA를 **대체하지 않고 생성**합니다 — 산수는 여전히 HPA 공식이고, KEDA는 쿼리 결과를 external 창으로 넣어주는 쪽.

## Step 3. 같은 발화 실험 — 결과도 같은가

```bash
# 터미널 1
kubectl get hpa keda-hpa-podinfo -n scalelab -w
# 터미널 2
kubectl run vegeta --rm -i --restart=Never -n scalelab \
  --image=peterevans/vegeta:latest --requests=cpu=500m -- sh -c \
  "echo 'GET http://podinfo.scalelab.svc:9898/' | vegeta attack -rate=300 -duration=180s | vegeta report"
```

예상: lab-01과 동일하게 300/50 → 6 replicas. 도구가 달라도 공식과 target 산정(13)이 같으니 결과가 같습니다 — **본질은 도구가 아니라 숫자의 근거**입니다.

## Step 4. scale-to-zero — 능력과 함정을 같이

부하를 끊고, min을 0으로:

```bash
kubectl patch scaledobject podinfo -n scalelab --type=merge \
  -p '{"spec":{"minReplicaCount":0,"idleReplicaCount":0}}'
# cooldownPeriod(120s) 경과 후
kubectl get pods -n scalelab -l app=podinfo -w    # → 0개까지 감소!
```

HPA 단독으론 불가능한 광경(minReplicas ≥ 1)입니다. 이제 함정 — 유저가 온다면?

```bash
kubectl run probe --rm -i --restart=Never -n scalelab --image=curlimages/curl -- \
  -s -m 5 -o /dev/null -w "%{http_code}\n" http://podinfo.scalelab.svc:9898/ || echo "FAILED"
```

예상: **실패.** 엔드포인트가 0개입니다. 더 나쁜 것 — 트리거가 Prometheus의 앱 메트릭인데, **Pod가 0이면 그 메트릭을 낼 자도 0**입니다: 요청이 와도 rate는 0 그대로 → 깨워줄 신호가 없습니다(닭-달걀).

```
scale-to-zero가 성립하는 조건: "일감"이 Pod 밖에 쌓일 것
  ✔ SQS/Kafka 큐 길이 (워커 패턴)  ✔ cron (시간표)  ✘ HTTP 직접 유입 (add-on 필요 — 프록시가 요청을 잡아두고 깨움)
```

원상 복구:

```bash
kubectl patch scaledobject podinfo -n scalelab --type=merge -p '{"spec":{"minReplicaCount":2,"idleReplicaCount":null}}'
```

✅ **0은 큐 기반 워커의 특권**입니다 — HTTP 서비스에 함부로 켜면 "첫 손님이 영원히 노크하는 가게"가 됩니다.

## Step 5. 두 경로 총정리 (산출물)

```markdown
| | Prometheus Adapter | KEDA |
|---|---|---|
| 설정 단위 | helm 규칙(전역) + HPA(개별) | ScaledObject(개별) — 셀프서비스 친화 |
| 메트릭 창 | custom.metrics | external.metrics |
| 소스 | Prometheus만 | 50+ (SQS, Kafka, CloudWatch, cron…) |
| scale-to-zero | ✘ | ✔ (큐/이벤트 워크로드) |
| 우리 팀 선택: __ — 근거: __ |

# target 산정 기록 (13 → 15 사슬)
- 무릎: __ rps / 측정 replicas: __ → Pod당 __ × 0.7 = target __
- maxReplicas: 피크 __ rps ÷ target + 여유 = __
- 검증: 300rps 실험에서 평형 replicas = 예측치 ✓
```

## 정리

```bash
bash cleanup.sh
```
