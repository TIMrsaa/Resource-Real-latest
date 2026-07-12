# Lab 02 — Kafka 기반 ScaledObject

## 학습 확인 포인트

- [ ] Strimzi Operator 로 Kafka in-cluster 띄움
- [ ] notification-service 가 Kafka topic lag 기반 스케일
- [ ] partition 수와 replicas 한계 이해

> **🌱 핵심 개념 미리보기**
> - **Kafka topic / partition**: 메시지 채널을 N 개로 분할. 각 partition 은 한 consumer 가 독점.
> - **Consumer Group**: 같은 group 의 consumer 들이 partition 을 나눠 처리. 병렬도 = partition 수.
> - **Lag**: 토픽의 마지막 메시지 offset 과 consumer 의 현재 offset 차이. 처리 지연도 지표.
> - **Strimzi Operator**: Kafka 클러스터/토픽을 K8s CRD 로 관리. KafkaNodePool, Kafka, KafkaTopic 리소스.
> - **partition = max replicas**: 한 group 안에서 partition 보다 더 많은 consumer 는 idle. 스케일 상한 = partition 수.

## 1. Strimzi Operator 설치

```bash
helm repo add strimzi https://strimzi.io/charts/
helm install strimzi-kafka-operator strimzi/strimzi-kafka-operator \
  -n kafka --create-namespace \
  --set watchAnyNamespace=true \
  --wait

kubectl get pods -n kafka
```

기대:
```
strimzi-cluster-operator-xxx   1/1   Running
```

## 2. Kafka 클러스터 + Topic 생성

```bash
kubectl apply -f manifests/strimzi-kafka.yaml

# 약 2~3분 후 Ready
kubectl wait --for=condition=Ready kafka/my-cluster -n kafka --timeout=300s
kubectl get kafka,kafkanodepool,kafkatopic -n kafka
```

기대:
```
NAME                                READY   ...
kafka.kafka.strimzi.io/my-cluster   True    ...

NAME                       READY
kafkanodepool/dual-role    True

NAME                                          PARTITIONS  REPLICATION
kafkatopic.kafka.strimzi.io/notifications     3           1
```

> **🧠 KafkaNodePool 의 의미 (Strimzi 0.39+)**
> 예전엔 Kafka 리소스 하나가 broker 설정/스토리지/role 다 포함 → 변경 시 cluster 전체 재시작.
> 0.39+ 부터 NodePool 로 broker 묶음을 분리 (역할별/크기별). 한 NodePool 만 rolling 가능 → 운영 영향 최소화.
> `dual-role` = controller + broker 한 Pod. 학습용. 운영은 보통 분리.

## 3. notification-service 의 KAFKA_BROKERS 갱신

```bash
kubectl set env deploy/notification-service -n order \
  KAFKA_BROKERS=my-cluster-kafka-bootstrap.kafka:9092 \
  KAFKA_TOPIC=notifications \
  KAFKA_GROUP=notification-service

kubectl rollout status deploy/notification-service -n order
```

→ 이전 모듈 09 에서 CrashLoop 였던 notification-service 가 정상 Running.

## 4. ScaledObject 적용

```bash
kubectl apply -f manifests/kafka-scaledobject.yaml
kubectl get scaledobject -n order
```

## 5. 0 으로 줄어드는지 watch

```bash
watch -n3 'kubectl get hpa -n order keda-hpa-notification-service; kubectl get pods -n order -l app.kubernetes.io/name=notification-service'
```

기대 (cooldown 후): replicas=0.

## 6. Kafka topic 에 메시지 produce

```bash
# 임시 producer Pod
kubectl run kafka-producer --rm -it --image=confluentinc/cp-kafka:7.6.0 \
  -n kafka \
  --command -- bash -c "for i in \$(seq 1 500); do echo '{\"to\":\"u'\$i'\",\"msg\":\"hello'\$i'\"}'; done | kafka-console-producer.sh --broker-list my-cluster-kafka-bootstrap:9092 --topic notifications"
```

→ 500 건 produce.

## 7. lag 폭증 → 스케일 업 관찰

watch:
```
HPA TARGETS         REPLICAS
... 500/10          3     ← max=3 (partition 수)
```

> 중요: replicas 가 partition 수(3)를 넘지 못함. 4번째 Pod 는 만들어져도 idle.

> **🧠 partition 한계의 진짜 이유**
> Kafka 의 consumer 할당은 group coordinator 가 partition rebalance 로 처리. 한 partition 은 한 consumer 만 점유 가능 (ordering 보장).
> 따라서 partition=3, consumer=10 이면 3 개만 active, 7 개는 partition 없이 대기.
> 처리량 늘리려면 토픽 partition 자체를 늘려야 함 (`kafka-topics.sh --alter --partitions 10`). 단, partition 줄이는 건 불가.

## 8. lag 모니터 (선택)

```bash
# Strimzi 0.39+ KafkaNodePool 사용 시 Pod 이름은 my-cluster-<nodepool>-0 형식.
# 본 매니페스트의 nodepool 이름은 dual-role 이지만, 안전하게 라벨로 동적 조회:
KAFKA_POD=$(kubectl get pod -n kafka \
  -l strimzi.io/cluster=my-cluster,strimzi.io/broker-role=true \
  -o jsonpath='{.items[0].metadata.name}')

kubectl exec -n kafka "${KAFKA_POD}" -- bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group notification-service
```

> **🧠 라벨 selector 로 Pod 조회하는 이유**
> Strimzi 의 Pod 이름은 NodePool 명에 의존 (`my-cluster-dual-role-0`, `my-cluster-broker-1` 등). 매니페스트 NodePool 이름이 바뀌면 이름 하드코딩은 즉시 깨짐.
> `strimzi.io/cluster=my-cluster` = 어느 Kafka cluster 소속인지, `strimzi.io/broker-role=true` = broker 역할 Pod 인지 (controller-only Pod 제외).
> 두 라벨 AND 로 broker Pod 만 정확히 골라냄 → NodePool 재명명/추가 시에도 안전. K8s selector 의 표준 방식.

기대 컬럼:
- `CURRENT-OFFSET`: 컨슈머가 처리한 위치
- `LOG-END-OFFSET`: 토픽의 가장 최근 위치
- `LAG`: 차이

> **🧠 KEDA Kafka scaler 가 lag 을 가져오는 방식**
> KEDA 가 직접 broker 에 접속해 `__consumer_offsets` 토픽을 조회 → consumer group 별 offset 과 토픽 LEO(log-end-offset) 차이 계산.
> sasl/tls 인증이 필요한 운영 클러스터는 ScaledObject 의 `authenticationRef` + TriggerAuthentication 으로 자격증명 주입.
> partition 별 lag 의 합산이 desired Pod 수 산정 기준 → 한쪽 partition 만 적체돼도 전체 스케일 가능.

## 9. 처리 완료 후 0 으로

5 분 후 lag 가 임계 미만 → cooldown → 0.

## 10. 정리

```bash
kubectl delete -f manifests/kafka-scaledobject.yaml
kubectl delete -f manifests/strimzi-kafka.yaml -n kafka
helm uninstall strimzi-kafka-operator -n kafka
kubectl delete ns kafka
```

## 학습 확인 질문

1. Kafka topic 의 partition 수와 KEDA maxReplicaCount 관계는?
2. 큐 처리 속도가 빠른데 Pod 수가 너무 많이 늘어나면? (over-scaling 방지)
3. Strimzi 가 만드는 Kafka NodePool / Kafka 리소스의 차이는?

다음: [quiz.md](./quiz.md)
