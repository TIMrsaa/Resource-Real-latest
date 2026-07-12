# Lab 01 — 신원과 스토리지 보장 검증

> 사전 조건: gp3 StorageClass (모듈 08에서 생성 — 없으면 그 모듈 manifests/storage.yaml의 StorageClass만 재적용)

## Step 1. 순차 기동 관찰

터미널 1: `kubectl get pods -l app=db -w`

터미널 2:
```bash
kubectl apply -f manifests/statefulset.yaml
```

터미널 1 예상 출력 (순서가 핵심):
```
db-0   0/1   Pending → ContainerCreating → Running(0/1) → 1/1
db-1   0/1   Pending          ← db-0이 Ready 된 후에야 등장!
db-1   1/1   Running
db-2   0/1   Pending          ← db-1 다음
db-2   1/1   Running
```

✅ Deployment(모듈 04 — 동시에 우르르)와 정반대. **하나가 Ready 되어야 다음.**

## Step 2. 멤버별 PVC 확인

```bash
kubectl get pvc -l app=db
```

예상 출력:
```
data-db-0   Bound   pvc-aaa...   1Gi   gp3
data-db-1   Bound   pvc-bbb...   1Gi   gp3
data-db-2   Bound   pvc-ccc...   1Gi   gp3      ← 멤버 수만큼, 이름이 결합을 보여줌
```

## Step 3. 멤버 직통 DNS

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: dnsutil
  labels: { run: dnsutil }
spec:
  containers:
    - name: dnsutil
      image: registry.k8s.io/e2e-test-images/agnhost:2.53
      args: ["sleep", "3600"]
EOF
kubectl wait --for=condition=Ready pod/dnsutil
kubectl exec dnsutil -- nslookup db-1.db.default.svc.cluster.local
kubectl exec dnsutil -- nslookup db    # Headless: 3개 IP 전부
```

✅ `db-1`을 **지명해서** 연결 가능 — "primary는 db-0" 같은 토폴로지 설정의 토대.

## Step 4. 핵심 실험 — 죽여도 같은 신원, 같은 디스크

```bash
# db-1의 디스크에 신원 표식을 남깁니다
kubectl exec db-1 -- sh -c 'echo "I am db-1, my precious data" > /data/identity.txt'
IP_BEFORE=$(kubectl get pod db-1 -o jsonpath='{.status.podIP}')

# 살해
kubectl delete pod db-1
kubectl wait --for=condition=Ready pod/db-1 --timeout=180s

# 검증
kubectl exec db-1 -- cat /data/identity.txt
IP_AFTER=$(kubectl get pod db-1 -o jsonpath='{.status.podIP}')
echo "IP: $IP_BEFORE → $IP_AFTER"
kubectl get pvc data-db-1 -o jsonpath='{.spec.volumeName}'; echo
```

예상 출력:
```
I am db-1, my precious data     ← 데이터 생존!
IP: 192.168.a.a → 192.168.b.b   ← IP는 바뀜 (그래서 DNS 이름을 쓰는 것)
pvc-bbb...                       ← 같은 PV
```

✅ **3가지가 한 번에 검증**: ① 정확히 "db-1"로 부활 ② 같은 PVC 재부착(데이터 보존) ③ IP는 바뀌므로 통신은 반드시 DNS 이름으로.

## Step 5. 스케일인 → PVC는 남습니다

```bash
kubectl scale statefulset db --replicas=2     # db-2가 (역순이라) 제거됨
kubectl get pods -l app=db
kubectl get pvc -l app=db
```

예상: Pod는 2개인데 PVC는 **3개 그대로** — `data-db-2`가 데이터를 품고 대기.

```bash
kubectl scale statefulset db --replicas=3     # 다시 늘리면
kubectl wait --for=condition=Ready pod/db-2 --timeout=180s
kubectl exec db-2 -- ls /data                  # 예전 데이터가 그대로 (이전에 썼다면)
```

✅ "줄였다 늘려도 멤버 데이터 복원" — 그리고 진짜로 버릴 때는 PVC를 **명시적으로** 지워야 한다는 뜻이기도 합니다 (비용!).

## 정리

다음 lab에서 계속 사용. dnsutil만 유지.
