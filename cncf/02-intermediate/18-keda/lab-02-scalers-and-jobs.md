# Lab 02 — 큐 스케일러, ScaledJob, 그리고 방어 장치

실제 큐(RabbitMQ)로 스케일하고, ScaledObject와 ScaledJob의 처리 모델 차이를 몸으로 확인합니다.

전제: lab-01의 클러스터(kind: keda), helm.

## Step 1. RabbitMQ — 큐 신호원

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1
helm install rabbit bitnami/rabbitmq -n queue --create-namespace \
  --set auth.username=user --set auth.password=pass \
  --set persistence.enabled=false >/dev/null
kubectl -n queue rollout status statefulset/rabbit-rabbitmq --timeout=300s

kubectl -n queue create secret generic rabbit-conn \
  --from-literal=host="amqp://user:pass@rabbit-rabbitmq.queue.svc:5672/" >/dev/null
```

## Step 2. TriggerAuthentication — KEDA의 자격증명

```bash
kubectl apply -n queue -f - <<'EOF'
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata: { name: rabbit-auth }
spec:
  secretTargetRef:
    - { parameter: host, name: rabbit-conn, key: host }
EOF

cat <<'EOF'
★ 신뢰 경계 관찰 (07):
  KEDA operator가 이 자격증명으로 RabbitMQ에 접속해 큐 길이를 폴링합니다
  → KEDA는 우리의 큐·DB·Prometheus에 접근 권한을 가진 주체입니다
  → keda 네임스페이스 침해 = 그 자격증명 전부의 침해
  → 방어: Secret 접근 제한, podIdentity(IRSA) 사용, 최소 권한(읽기 전용 사용자)
EOF
```

## Step 3. ScaledObject로 큐 소비 워커

```bash
kubectl -n queue create configmap worker-code --from-literal=worker.py='
import os, time, pika, signal, sys
stop = False
def handler(sig, frame):
    global stop; stop = True; print("graceful shutdown 시작", flush=True)
signal.signal(signal.SIGTERM, handler)   # ★ 스케일다운 시 메시지 유실 방지

conn = pika.BlockingConnection(pika.URLParameters(os.environ["AMQP_URL"]))
ch = conn.channel(); ch.queue_declare(queue="tasks", durable=True)
ch.basic_qos(prefetch_count=1)
while not stop:
    method, props, body = ch.basic_get("tasks", auto_ack=False)
    if body is None:
        time.sleep(1); continue
    print(f"처리 중: {body.decode()}", flush=True)
    time.sleep(3)                        # 작업 시간
    ch.basic_ack(method.delivery_tag)    # ★ 처리 완료 후에만 ack
print("종료", flush=True)
' >/dev/null

kubectl -n queue apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: consumer }
spec:
  replicas: 0
  selector: { matchLabels: { app: consumer } }
  template:
    metadata: { labels: { app: consumer } }
    spec:
      terminationGracePeriodSeconds: 30      # ★ graceful shutdown 시간 확보
      containers:
        - name: w
          image: python:3.12-slim
          command: ["sh","-c","pip install -q pika 2>/dev/null && python /src/worker.py"]
          env:
            - name: AMQP_URL
              valueFrom: { secretKeyRef: { name: rabbit-conn, key: host } }
          volumeMounts: [{ name: src, mountPath: /src }]
      volumes: [{ name: src, configMap: { name: worker-code } }]
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata: { name: consumer-so }
spec:
  scaleTargetRef: { name: consumer }
  minReplicaCount: 0
  maxReplicaCount: 8
  pollingInterval: 10
  cooldownPeriod: 30
  triggers:
    - type: rabbitmq
      metadata:
        protocol: amqp
        queueName: tasks
        mode: QueueLength
        value: "5"                # ★ Pod 하나가 큐 5개를 담당
        activationValue: "1"      # 1개라도 있으면 0→1
      authenticationRef: { name: rabbit-auth }
EOF
sleep 20
kubectl -n queue get scaledobject consumer-so
kubectl -n queue get deploy consumer
```

## Step 4. 메시지를 넣어 스케일 관찰

```bash
kubectl -n queue run producer --rm -i --restart=Never --image=python:3.12-slim \
  --env="AMQP_URL=amqp://user:pass@rabbit-rabbitmq.queue.svc:5672/" -- \
  sh -c 'pip install -q pika 2>/dev/null && python -c "
import os, pika
c = pika.BlockingConnection(pika.URLParameters(os.environ[\"AMQP_URL\"]))
ch = c.channel(); ch.queue_declare(queue=\"tasks\", durable=True)
for i in range(40): ch.basic_publish(\"\", \"tasks\", f\"task-{i}\".encode())
print(\"40개 발행\")
"' 2>/dev/null

for i in 1 2 3 4 5 6; do
  sleep 15
  R=$(kubectl -n queue get deploy consumer -o jsonpath='{.spec.replicas}')
  echo "  t+$((i*15))s  replicas=$R"
done
```

예상: 큐 40개 ÷ value 5 = 8 replicas(max)까지 증가. ✅ **desired = ceil(queueLength / value)** — HPA의 표준 공식이 큐 길이에 적용된 것.

## Step 5. graceful shutdown의 중요성

```bash
cat <<'EOF'
큐가 비면 KEDA가 스케일다운 → Pod에 SIGTERM → 30초(terminationGracePeriodSeconds)

만약 worker가 SIGTERM을 무시하면?
  처리 중이던 메시지가 ack 안 된 채 Pod가 죽습니다
  → RabbitMQ가 재전송(다행) 또는 유실(auto_ack=True 였다면 확정 유실)

★ ScaledObject 워커의 필수 조건:
  ① SIGTERM 핸들러 (새 메시지 수신 중단, 진행 중인 것만 마무리)
  ② terminationGracePeriodSeconds ≥ 최대 처리 시간
  ③ 처리 완료 후 ack (auto_ack 금지)
  → 이것 없이 scale-to-zero를 켜면 메시지가 조용히 사라집니다
EOF
kubectl -n queue logs -l app=consumer --tail=3 2>/dev/null | head -3
```

## Step 6. ScaledJob — 긴 작업의 모델

```bash
kubectl -n queue apply -f - <<'EOF'
apiVersion: keda.sh/v1alpha1
kind: ScaledJob
metadata: { name: long-task }
spec:
  jobTargetRef:
    backoffLimit: 2
    template:
      spec:
        restartPolicy: Never
        containers:
          - name: task
            image: busybox
            command: ["sh","-c","echo '긴 작업 시작'; sleep 20; echo '완료'"]
  pollingInterval: 15
  maxReplicaCount: 5
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  scalingStrategy: { strategy: "accurate" }   # 대기 중인 잡을 고려해 과잉 생성 방지
  triggers:
    - type: rabbitmq
      metadata: { protocol: amqp, queueName: tasks, mode: QueueLength, value: "3" }
      authenticationRef: { name: rabbit-auth }
EOF
sleep 40
kubectl -n queue get jobs | head -6
kubectl -n queue get pods | grep long-task | head -4
```

예상: 큐 길이에 따라 **Job이 여러 개 생성**되고, 각 Job의 Pod가 처리 후 종료됩니다.

```bash
cat <<'EOF'

ScaledObject vs ScaledJob (theory §4):
| | ScaledObject | ScaledJob |
|---|---|---|
| 모델 | 워커 상주, 큐 폴링 | 메시지(들)마다 Job |
| 종료 | Pod 유지 | 처리 후 종료 |
| 재시도 | 앱이 처리 | backoffLimit |
| 긴 작업 | 스케일다운 시 위험 | ✅ 안전(잡 완료까지 살아있음) |
| 대량 짧은 메시지 | ✅ 효율 | ❌ Pod 생성 폭주(API 서버 부하) |
| 선택 | 짧고 많습니다 | 길고 격리가 필요합니다 |
EOF
```

## Step 7. 방어 장치 — fallback과 알람

```bash
kubectl -n queue patch scaledobject consumer-so --type merge -p '{
  "spec": {
    "fallback": { "failureThreshold": 3, "replicas": 2 },
    "advanced": { "restoreToOriginalReplicaCount": true }
  }
}'

cat <<'EOF'
★ fallback: 스케일러(RabbitMQ)가 3회 연속 실패하면 replicas를 2로 고정
   → 외부 시스템 장애 시 "0으로 떨어져 아무것도 처리 못 하는" 사태 방지

★ 필수 알람 (theory §7):
   keda_scaler_errors_total          스케일러 오류 (인증·연결)
   keda_scaler_metrics_value         현재 메트릭 값 (이상 감지)
   keda_scaled_object_errors_total   ScaledObject 수준 오류
   + HPA의 조건(ScalingActive=False)

★ 폴링 부하 계산:
   ScaledObject 수 × 트리거 수 ÷ pollingInterval = 외부 시스템 QPS
   200개 SO × 1 트리거 ÷ 10초 = 20 QPS를 Prometheus/큐가 받습니다
EOF
```

## Step 8. 산출물

```markdown
# KEDA 운영 카드
- 워커 요구사항: SIGTERM 핸들러 + gracePeriod ≥ 처리시간 + 처리 후 ack
- ScaledJob: 긴 작업·격리·재시도 / ScaledObject: 짧고 많은 메시지
- fallback으로 스케일러 장애 시 안전 replicas
- 알람: keda_scaler_errors_total, ScalingActive 조건
- 폴링 부하 = SO 수 × 트리거 ÷ interval — 외부 시스템 용량 확인
- 신뢰 경계: KEDA operator가 큐·DB 자격증명 보유 → 최소 권한·podIdentity
- 사용자 대면 경로에는 minReplicaCount ≥ 1 (콜드스타트)
```

## 정리

```bash
bash cleanup.sh
```
