# Lab 03 — StatefulSet (Redis)

## 학습 확인 포인트

- [ ] StatefulSet의 Pod 이름이 순차임을 봤다 (`redis-0`, `redis-1`, `redis-2`)
- [ ] volumeClaimTemplates로 Pod별 PVC가 자동 생성됨을 봤다
- [ ] Headless Service로 Pod 별 DNS가 만들어지는 걸 확인했다

> **🌱 핵심 개념 미리보기**
> - **StatefulSet**: 상태 있는(stateful) 앱용 컨트롤러. Pod 이름이 순차(`-0`, `-1`, ...) 고정 + 순차 시작/종료.
> - **volumeClaimTemplates**: Pod별로 PVC를 자동 생성 → 각자 독립 EBS 보유.
> - **Headless Service**: `clusterIP: None`. ClusterIP 없이 Pod별 DNS만 제공 (`pod-0.svc-name.ns.svc.cluster.local`).
> - **순차 보장**: redis-0 Ready 후에야 redis-1 시작 → master-replica 구성 등에 유용.
> - **Deployment vs StatefulSet**: 전자는 stateless (Pod 이름 랜덤, PVC 공유), 후자는 stateful (이름 고정, PVC 개별).

## 1. 적용

```bash
kubectl apply -f manifests/redis-statefulset.yaml
kubectl get sts,pods,pvc -l app=redis --watch
```

기대 (순차로):
```
redis-0   0/1   Pending     0   0s
redis-0   0/1   ContainerCreating   0   2s
redis-0   1/1   Running     0   10s
redis-1   0/1   Pending     0   10s    ← 0번이 Ready 된 후 시작
redis-1   1/1   Running     0   20s
redis-2   ...
```

## 2. Pod별 PVC 자동 생성

```bash
kubectl get pvc -l app=redis
```

기대:
```
NAME             STATUS   VOLUME       CAPACITY   ACCESS MODES   STORAGECLASS
data-redis-0     Bound    pvc-aaa      1Gi        RWO            gp3
data-redis-1     Bound    pvc-bbb      1Gi        RWO            gp3
data-redis-2     Bound    pvc-ccc      1Gi        RWO            gp3
```

→ Pod별 별도 EBS 볼륨, 데이터 격리.

> **🧠 PVC 이름 규칙 — `<volumeClaimTemplate.name>-<sts.name>-<ordinal>`**
> 위 예: template 이름이 `data`, sts 이름이 `redis` 라서 → `data-redis-0`, `data-redis-1` ...
> 이 규칙 덕분에 redis-0 이 죽어 다시 만들어져도 같은 PVC(`data-redis-0`) 를 재사용 → 데이터 보존됨.
> Deployment의 ReplicaSet 해시 prefix 와는 정반대 (Deployment Pod은 매번 새 이름).

## 3. Headless Service 동작 확인

```bash
kubectl run -it --rm dbg --image=alpine -- sh
apk add --no-cache bind-tools redis

# Service 자체 조회 (Headless 면 ClusterIP 없이 Pod IP들 반환)
nslookup redis-hl

# Pod별 DNS
nslookup redis-0.redis-hl
nslookup redis-1.redis-hl
nslookup redis-2.redis-hl
```

각각 다른 IP가 반환됩니다.

```bash
# 특정 Pod에 직접 접속
redis-cli -h redis-0.redis-hl SET hello "from-redis-0"
redis-cli -h redis-1.redis-hl SET hello "from-redis-1"
redis-cli -h redis-0.redis-hl GET hello       # → from-redis-0
redis-cli -h redis-1.redis-hl GET hello       # → from-redis-1
```

→ 각 Pod 가 **독립된 데이터** 보유. (Redis Cluster 모드는 아님 — 단순 multi-instance)

> **🧠 Headless Service의 정체**
> 일반 Service는 ClusterIP가 있고 그 IP로 라운드 로빈 분배.
> Headless는 ClusterIP 없음 → DNS 질의 시 **모든 Pod IP를 그대로 반환** (A 레코드 다중).
> 또한 Pod별 sub-domain (`redis-0.redis-hl.default.svc.cluster.local`) 자동 생성 → 특정 Pod 핀포인트 호출 가능.
> Cassandra, Kafka, Zookeeper 같은 P2P 클러스터는 이 방식 필수.

## 4. Pod 재시작 후 데이터 보존

```bash
redis-cli -h redis-0.redis-hl SET test "before-restart"
exit
```

호스트로 돌아와서:
```bash
kubectl delete pod redis-0
kubectl get pods -l app=redis --watch
```

기대: `redis-0` 이 다시 만들어짐 (같은 이름).

```bash
kubectl run -it --rm dbg --image=alpine -- sh
apk add -q redis
redis-cli -h redis-0.redis-hl GET test
exit
```

기대: `before-restart` — 데이터 보존됨 (같은 PVC를 재사용).

## 5. 스케일링

```bash
kubectl scale sts/redis --replicas=5
kubectl get pods -l app=redis --watch
```

기대: `redis-3`, `redis-4` 가 순차로 추가. 새 PVC도 자동 생성.

다시 줄이기:
```bash
kubectl scale sts/redis --replicas=2
kubectl get pods,pvc -l app=redis
```

기대:
- Pod: `redis-0`, `redis-1` 만 남음 (`redis-2`, `redis-3`, `redis-4` 는 역순 종료)
- **PVC는 그대로 남아있음** — StatefulSet 삭제 시에도 데이터 유실 방지

> **🧠 PVC가 살아남는 이유 — 의도된 안전장치**
> StatefulSet은 보통 DB/큐 같은 stateful 워크로드 → 사용자 실수로 sts 삭제해도 데이터는 보존돼야 함.
> 1.27+ 에선 `persistentVolumeClaimRetentionPolicy` 로 정책 변경 가능 (`whenScaled: Delete`, `whenDeleted: Delete`).
> 운영 권장: 명시적으로 PVC 정리 전엔 그대로 두기 → 백업 후 수동 삭제.

## 6. 정리

```bash
kubectl delete -f manifests/redis-statefulset.yaml
kubectl get pvc -l app=redis      # 여전히 남아있음

# PVC도 명시적으로 삭제
kubectl delete pvc -l app=redis
```

EBS 볼륨이 실제로 사라졌는지 확인:
```bash
sleep 30
aws ec2 describe-volumes \
  --filters "Name=tag:kubernetes.io/created-for/pvc/name,Values=data-redis-0,data-redis-1,data-redis-2" \
  --query 'Volumes[].[VolumeId,State]' --output table
```

기대: 빈 결과 또는 `deleted` 상태.

## 학습 확인 질문

1. StatefulSet의 Pod 시작 순서가 순차인 것이 어떤 워크로드에 중요한가?
2. StatefulSet을 삭제할 때 PVC를 같이 삭제하지 않는 이유는?
3. `redis-0` 의 데이터를 `redis-1` 이 자동으로 복제하게 만들려면 (Redis 자체 기능 없이 K8s만으로) 가능한가?

다음: [quiz.md](./quiz.md)
