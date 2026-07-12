# Lab 02 — 순서, partition 카나리, 강제 삭제의 경계

## Step 1. 업데이트는 "큰 번호부터 하나씩"

터미널 1: `kubectl get pods -l app=db -w`

터미널 2:
```bash
kubectl set image statefulset/db db=registry.k8s.io/e2e-test-images/agnhost:2.52
```

터미널 1 예상 순서:
```
db-2   Terminating → 새 db-2 Running    ← 가장 큰 번호부터
db-1   Terminating → 새 db-1 Running
db-0   Terminating → 새 db-0 Running    ← primary(관례상 0)가 마지막 = 가장 안전
```

## Step 2. partition 카나리 — 상태 워크로드의 점진 배포

```bash
# 먼저 원복하되, partition=2로 "순번 2 이상만 업데이트 허용"
kubectl patch statefulset db -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":2}}}}'
kubectl set image statefulset/db db=registry.k8s.io/e2e-test-images/agnhost:2.53
kubectl rollout status statefulset/db --timeout=120s

# 버전 분포 확인
kubectl get pods -l app=db -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.spec.containers[0].image}{"\n"}{end}'
```

예상 출력:
```
db-0: ...agnhost:2.52      ← partition 미만: 옛 버전 유지
db-1: ...agnhost:2.52
db-2: ...agnhost:2.53      ← 카나리 1마리만 새 버전
```

✅ db-2로 검증한 뒤 단계적 확산:

```bash
kubectl patch statefulset db -p '{"spec":{"updateStrategy":{"rollingUpdate":{"partition":0}}}}'
kubectl rollout status statefulset/db
```

> 💡 비교: Deployment의 카나리는 트래픽 비율(Gateway weight), StatefulSet의 카나리는 **멤버 번호** 기준 — 상태 워크로드에선 "어느 멤버가 새 버전인가"가 더 의미 있기 때문.

## Step 3. Pending 멤버가 줄을 세웁니다 (순서의 비용)

```bash
# db-1을 일부러 못 뜨게 (없는 이미지)
kubectl patch statefulset db --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"registry.k8s.io/no-such:latest"}]'
kubectl delete pod db-1     # 재생성 유도
sleep 20; kubectl get pods -l app=db
```

예상:
```
db-0   1/1   Running
db-1   0/1   ErrImagePull    ← 여기서 막힘
db-2   1/1   Running          (이미 떠 있던 것은 유지)
```

이 상태에서 이미지를 또 바꿔도 **db-2부터의 업데이트가 db-1에서 정체**됩니다 — 순차 보장의 대가. 복구:

```bash
kubectl patch statefulset db --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"registry.k8s.io/e2e-test-images/agnhost:2.53"}]'
kubectl delete pod db-1
kubectl rollout status statefulset/db
```

## Step 4. 강제 삭제 — 경계선 학습 (개념 실습)

노드 장애로 db-0이 `Terminating`에 영원히 갇혔다고 합시다. StatefulSet은 대체를 만들지 않습니다 — 왜?

```
같은 "db-0" 신원이 두 곳에 살아 있으면 (옛 노드에서 실제로는 살아있을 가능성)
→ 둘 다 자기가 db-0라며 디스크/복제에 쓰기 → 데이터 분기 (split-brain)
```

올바른 절차:
```bash
# ① 노드가 정말 죽었는지 확인 (콘솔/SSM) → ② 노드 객체 삭제 (kubelet이 없음을 확정)
# kubectl delete node <죽은노드>     ← 이것이 안전한 해소법
# ③ 최후수단으로만: kubectl delete pod db-0 --force --grace-period=0
```

✅ 외울 것: **force delete는 "물리적으로 죽었음을 사람이 보증"하는 서명입니다.**

## Step 5. PDB 한 장 얹기 (운영 마무리)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: db-pdb }
spec:
  minAvailable: 2
  selector:
    matchLabels: { app: db }
EOF
kubectl get pdb db-pdb
```

예상: `ALLOWED DISRUPTIONS: 1` — 노드 drain(모듈 35)이 동시에 2개 이상 못 빼갑니다. 3중 클러스터의 정족수(2) 보호.

## 정리

```bash
bash cleanup.sh
```
