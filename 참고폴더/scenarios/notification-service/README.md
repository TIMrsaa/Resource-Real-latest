# notification-service

Kafka topic을 컨슘하여 알림 발송을 시뮬레이션하는 워커 서비스.
**Part 3 KEDA Kafka 트리거 시연용**.

---

## SQS Worker vs Kafka Consumer (왜 둘 다?)

본 커리큘럼은 두 가지 메시징 패턴을 모두 다룹니다:

| 항목 | SQS (payment-service) | Kafka (notification-service) |
|------|----------------------|------------------------------|
| 모델 | Queue (1:1, 메시지 1개 = 1개 컨슈머만) | Topic + Partition (1:N pub/sub) |
| 순서 | FIFO 큐만 보장 | partition 내에서만 보장 |
| 처리량 | 중 | 매우 높음 (수백만 msg/s) |
| 보존 | 처리 후 삭제 (또는 14일) | 시간 기반 (7일 등) |
| 사용처 | 작업 큐, 이벤트 분배 | 이벤트 스트리밍, CDC, 분석 |
| AWS 매니지드 | SQS, MSK | MSK, Kinesis |

→ "결제(SQS)는 한번만 처리, 알림(Kafka)은 여러 구독자에게 발송" 같은 패턴 학습.

---

## 코드 한눈에 보기

```
main.go
  ├─ KAFKA_BROKERS, KAFKA_TOPIC, KAFKA_GROUP 환경변수 읽기
  ├─ kafka.NewReader(brokers, topic, group)
  │    → 같은 group의 컨슈머들이 partition을 자동 분배 (rebalance)
  ├─ Consumer 생성 + Handler 정의 (받은 메시지 로그)
  ├─ :9090 메트릭/헬스체크
  └─ Run() → 무한 루프로 ReadMessage()
                + ctx.Done()으로 graceful shutdown

consumer/kafka.go
  └─ 메시지 읽기 + Handler 호출 + 자동 commit
```

**Consumer Group 의 동작**:
```
Topic: notifications (3 partition)
  ├─ partition 0
  ├─ partition 1
  └─ partition 2

Consumer Group: notification-service
  ├─ Pod-A 가 partition 0 담당
  ├─ Pod-B 가 partition 1 담당
  └─ Pod-C 가 partition 2 담당

Pod 추가 (4번째) → Kafka가 rebalance → 하지만 partition이 3개라 1개는 idle
                                       (= maxReplicaCount는 partition 수 이하로!)

Pod 죽음 (B) → A 또는 C 가 partition 1 도 가져감 (자동 페일오버)
```

---

## 동작

1. `KAFKA_BROKERS`의 `KAFKA_TOPIC`을 `KAFKA_GROUP` 컨슈머 그룹으로 구독
2. 메시지 수신 시 로깅 (실제 알림 발송은 시뮬레이션)
3. 정상 처리 후 오프셋 커밋

---

## 환경변수

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `KAFKA_BROKERS` | `localhost:9092` | 콤마로 구분된 브로커 주소 (`b1:9092,b2:9092`) |
| `KAFKA_TOPIC` | `notifications` | 구독 토픽 |
| `KAFKA_GROUP` | `notification-service` | 컨슈머 그룹 ID |

**Consumer Group ID 의 의미**:
- 같은 group ID = 한 컨슈머 그룹 = partition 분담 처리 (load balance)
- 다른 group ID = 독립적 처리 (같은 메시지를 다른 group이 모두 받음 = pub/sub)

---

## 로컬 실행 (docker-compose 사용 권장)

```bash
# scenarios/ 루트에서 Kafka 시작
docker compose up -d kafka

# 토픽 자동 생성됨 (compose 설정으로) 또는 수동:
docker compose exec kafka kafka-topics --create \
  --topic notifications --partitions 3 --replication-factor 1 \
  --bootstrap-server kafka:9092

# notification-service 실행
KAFKA_BROKERS=localhost:9092 go run .

# 다른 터미널에서 메시지 발행
docker compose exec kafka kafka-console-producer \
  --topic notifications --bootstrap-server kafka:9092
> {"user_id":"u1","msg":"hello"}
# → notification-service 로그에 메시지 출력됨
```

---

## 테스트

```bash
go test ./...
```

---

## Part 3 KEDA 트리거

```yaml
# Part-3-13 kafka-scaledobject.yaml 참고
triggers:
  - type: kafka
    metadata:
      bootstrapServers: my-cluster-kafka-bootstrap.kafka:9092
      consumerGroup: notification-service
      topic: notifications
      lagThreshold: "10"          # lag 10개당 Pod 1개
      offsetResetPolicy: latest
```

**Consumer Lag 설명**:
```
producer offset:    100 (latest)
                     ↓
consumer offset:    87 (commit 한 마지막 위치)
                     ↑
lag = 100 - 87 = 13 (처리 못 한 메시지 13개)
```

lag > lagThreshold * partition 수 일 때 KEDA 가 Pod 추가.

**중요 한도**: `maxReplicaCount` 가 partition 수보다 크면 무의미.
→ strimzi-kafka.yaml에 `partitions: 3` → maxReplicaCount=3

---

## K8s에서 띄울 때 주의 (long-running consumer)

```yaml
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 30   # 컨슈머가 in-flight 메시지 처리 시간
      containers:
        - name: app
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh","-c","sleep 5"]   # 그레이스풀 종료 여유
```

이유: SIGTERM 받자마자 죽으면 처리 중인 메시지가 lost or 재처리됨.
ctx.Done() 신호 받고 → 현재 메시지 처리 완료 → commit → 종료 가 정석.
