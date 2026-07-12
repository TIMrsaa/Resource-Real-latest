# Lab 01 — Strimzi 오퍼레이터로 Kafka 운영하기

> Strimzi를 설치하고, Kafka 클러스터를 CR로 배포하고, 토픽을 관리하고, 09에서 배운 Kafka의 스테이트풀 함정을 Strimzi가 어떻게 다루는지 확인합니다. kind에서 소규모(브로커 1~3)로 개념을 익힙니다.

## 0. 준비

```bash
kind create cluster --name strimzi
kubectl create namespace kafka
```

## 1. Strimzi 오퍼레이터 설치 (39의 Rook과 대비)

```bash
# Strimzi 오퍼레이터 설치 (39에서 Rook 오퍼레이터를 깔았던 것과 같은 패턴)
kubectl create -f 'https://strimzi.io/install/latest?namespace=kafka' -n kafka

# 오퍼레이터 Pod 확인
kubectl -n kafka get pod -l name=strimzi-cluster-operator -w
# strimzi-cluster-operator-... Running
```

**39와 비교** — Rook 오퍼레이터가 `CephCluster` CR을 기다렸듯, Strimzi 오퍼레이터는 `Kafka` CR을 기다립니다. 오퍼레이터 자체는 아직 아무 Kafka도 운영하지 않습니다(대상 CR이 없으므로).

```bash
# 오퍼레이터가 감시하는 CRD 확인 (08의 CRD 개념)
kubectl get crd | grep kafka.strimzi.io
# kafkas.kafka.strimzi.io
# kafkatopics.kafka.strimzi.io
# kafkausers.kafka.strimzi.io
# kafkaconnects / kafkarebalances ...
```

각 CRD가 Kafka 운영의 한 측면(클러스터·토픽·유저·리밸런싱)을 선언형으로 표현합니다 — 08에서 배운 "CRD = 도메인 어휘의 확장".

## 2. Kafka 클러스터 배포 (KRaft 모드)

```yaml
# kafka.yaml — 최신 Strimzi는 KRaft(ZooKeeper 제거) 권장
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaNodePool
metadata:
  name: dual-role
  namespace: kafka
  labels:
    strimzi.io/cluster: my-cluster
spec:
  replicas: 3                    # 브로커 3 (09의 복제 3)
  roles: [controller, broker]    # KRaft: controller와 broker 겸직
  storage:
    type: persistent-claim       # 05의 블록 (각 브로커의 영속 볼륨)
    size: 10Gi
    deleteClaim: false           # ★ 삭제해도 볼륨 보존 (09 데이터 안전)
---
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  name: my-cluster
  namespace: kafka
  annotations:
    strimzi.io/node-pools: enabled
    strimzi.io/kraft: enabled
spec:
  kafka:
    version: 3.7.0
    replicas: 3
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      default.replication.factor: 3
      min.insync.replicas: 2       # ★ 09의 ISR — 최소 2개 동기 복제본
  entityOperator:
    topicOperator: {}             # KafkaTopic CR을 관리
    userOperator: {}              # KafkaUser CR을 관리
```

```bash
kubectl apply -f kafka.yaml
# Strimzi가 브로커 StatefulSet·PVC·서비스를 생성 (39의 Rook이 OSD를 만들듯)
kubectl -n kafka get pod -w
# my-cluster-dual-role-0/1/2  Running   (브로커 3개)
kubectl -n kafka wait kafka/my-cluster --for=condition=Ready --timeout=300s
```

**관찰** — 회원님이 StatefulSet·PVC를 직접 만들지 않았습니다. `Kafka` CR 하나로 Strimzi가 09에서 손으로 신경 써야 했던 것(복제 팩터, ISR, 브로커별 영속 볼륨, 안티어피니티)을 설정했습니다. `min.insync.replicas: 2`가 바로 09 사고("쓰기가 충분히 복제되지 않음")를 막는 설정입니다.

## 3. 토픽 관리 — KafkaTopic CR

```yaml
# topic.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  name: orders
  namespace: kafka
  labels:
    strimzi.io/cluster: my-cluster
spec:
  partitions: 6         # 09의 파티션 (병렬성 단위)
  replicas: 3           # 09의 복제
  config:
    retention.ms: 604800000   # 7일 보존 (09의 로그 보존)
    segment.bytes: 1073741824
```

```bash
kubectl apply -f topic.yaml
kubectl -n kafka get kafkatopic
# NAME     CLUSTER      PARTITIONS   REPLICATION   READY
# orders   my-cluster   6            3             True
```

토픽을 kafka CLI가 아니라 kubectl로 만들었습니다 — GitOps(14·15)로 토픽을 선언형 관리할 수 있다는 뜻입니다(토픽도 Git에 커밋).

## 4. 메시지 생산·소비 (동작 확인)

```bash
# 생산자 (일회성 Pod)
kubectl -n kafka run producer -ti --image=quay.io/strimzi/kafka:latest-kafka-3.7.0 \
  --rm=true --restart=Never -- \
  bin/kafka-console-producer.sh --bootstrap-server my-cluster-kafka-bootstrap:9092 --topic orders
# > order-1
# > order-2
# (Ctrl+C)

# 소비자 (다른 터미널)
kubectl -n kafka run consumer -ti --image=quay.io/strimzi/kafka:latest-kafka-3.7.0 \
  --rm=true --restart=Never -- \
  bin/kafka-console-consumer.sh --bootstrap-server my-cluster-kafka-bootstrap:9092 --topic orders --from-beginning
# order-1
# order-2
```

## 5. 09의 함정 확인 — 브로커를 함부로 지우면?

```bash
# 브로커 Pod를 강제로 삭제해봅니다 (09 사고 재현 시도)
kubectl -n kafka delete pod my-cluster-dual-role-1

# StatefulSet이 즉시 같은 이름·같은 PVC로 재생성 (05의 StatefulSet 안정 ID)
kubectl -n kafka get pod -w
# my-cluster-dual-role-1  재생성 → 기존 PVC 재부착 → 데이터 유지
```

**핵심** — 브로커 Pod를 지워도 PVC(영속 볼륨)가 살아 있어 데이터가 유지됩니다(05의 StatefulSet + `deleteClaim: false`). 하지만 **여러 브로커를 동시에** 잃으면 `min.insync.replicas`를 못 채워 쓰기가 멈춥니다 — 그래서 실제 유지보수는 Strimzi의 롤링(하나씩, ISR 확인)을 따라야 합니다.

```bash
# Strimzi가 관리하는 롤링을 유발하는 방법 (설정 변경 → 오퍼레이터가 안전하게 순차 재시작)
# 예: config를 바꾸면 Strimzi가 브로커를 하나씩, ISR을 지키며 재시작
kubectl -n kafka annotate kafka my-cluster strimzi.io/manual-rolling-update=true
# → 오퍼레이터가 브로커를 순차 재시작 (09 사고와 반대: 오퍼레이터 절차)
```

## 6. 정리

```bash
kubectl delete -f topic.yaml
kubectl -n kafka delete kafka my-cluster
kubectl -n kafka delete kafkanodepool dual-role
# 오퍼레이터·PVC 정리는 cleanup.sh에서
```

## 정리

- Strimzi 오퍼레이터는 39의 Rook과 같은 패턴 — `Kafka` CR로 브로커·토픽·유저를 선언형 관리
- `min.insync.replicas`·복제 팩터·영속 볼륨을 CR이 설정 → 09에서 손으로 하던 안전장치를 코드화
- 토픽·유저도 CR → GitOps로 관리 가능
- 브로커 Pod 삭제는 PVC 덕에 견디지만, 다중 손실은 ISR 위반 → **유지보수는 오퍼레이터 롤링**(09 사고 방지)
- **★ Strimzi를 쓴다 = Kafka를 운영한다 + 그 운영을 오퍼레이터에 위임합니다** (39의 "시스템 vs 오케스트레이터")
