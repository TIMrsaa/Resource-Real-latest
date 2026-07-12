# Lab 02 — 롤링 업데이트 내부 관찰과 롤백

> lab-01의 `web` Deployment(replicas=3)가 떠 있는 상태에서 시작.

## Step 1. RS 교차 순간 포착 준비

터미널 1 (RS 감시 — 이 lab의 주인공):
```bash
kubectl get rs -l app=web -w
```

## Step 2. 이미지 업데이트 트리거

터미널 2:
```bash
kubectl set image deployment/web web=public.ecr.aws/nginx/nginx:1.28
kubectl rollout status deployment/web
```

터미널 1 예상 출력 (숫자 교차를 보라):
```
NAME             DESIRED   CURRENT   READY
web-7d4b9c8f6    3         3         3          ← 옛 RS
web-5f6a7b8c9    1         1         0          ← 새 RS 등장 (maxSurge:1)
web-5f6a7b8c9    1         1         1          ← 새 Pod Ready
web-7d4b9c8f6    2         2         2          ← 옛 RS 하나 감소 (maxUnavailable:0 지킴)
web-5f6a7b8c9    2         2         2
web-7d4b9c8f6    1         1         1
web-5f6a7b8c9    3         3         3
web-7d4b9c8f6    0         0         0          ← 옛 RS는 0개로 "보존"
```

✅ **검증 포인트**: 합계가 항상 3 이상 4 이하 — `maxSurge:1 / maxUnavailable:0` 계약 그대로. 그리고 옛 RS가 **삭제되지 않고 0으로 남았습니다.**

```bash
kubectl rollout status deployment/web
# → deployment "web" successfully rolled out
```

## Step 3. 리비전 이력과 롤백

```bash
kubectl rollout history deployment/web
```

예상 출력:
```
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

```bash
# 롤백 = 옛 RS를 다시 키우는 것
kubectl rollout undo deployment/web
kubectl get rs -l app=web
```

예상 출력:
```
web-7d4b9c8f6    3   3   3      ← 부활! (1.27)
web-5f6a7b8c9    0   0   0      ← 이번엔 이쪽이 0으로
```

✅ 롤백의 실체 = "보관해둔 설계도(RS)의 replicas 복원". 새 이미지 pull도 필요 없어서 빠릅니다.

## Step 4. 실패하는 업데이트 — 롤아웃이 "멈추는" 안전장치

```bash
kubectl set image deployment/web web=public.ecr.aws/nginx/nginx:does-not-exist
sleep 20 && kubectl get pods -l app=web
```

예상 출력:
```
web-7d4b9c8f6-aaa   1/1   Running        ← 옛 버전 3개 전부 무사
web-7d4b9c8f6-bbb   1/1   Running
web-7d4b9c8f6-ccc   1/1   Running
web-9z8y7x6w5-ddd   0/1   ErrImagePull   ← 새 버전 1개만 실패 중
```

✅ **검증 포인트**: maxUnavailable:0 덕분에 **서비스는 멀쩡합니다.** 롤아웃은 첫 교체에서 막혀 더 진행을 안 합니다 — 깨진 버전이 전체로 퍼지지 않는 빌트인 안전장치.

```bash
kubectl rollout status deployment/web --timeout=10s   # → error: ... deadline exceeded
kubectl rollout undo deployment/web                    # 복구
kubectl rollout status deployment/web                  # → successfully rolled out
```

## Step 5. `rollout restart` — template 불변 문제의 해법

```bash
kubectl rollout restart deployment/web
kubectl get pod -l app=web -o jsonpath='{.items[0].spec.containers[0].image}{"\n"}'  # 이미지 동일
kubectl get deploy web -o jsonpath='{.spec.template.metadata.annotations}{"\n"}'
```

예상 출력:
```
{"kubectl.kubernetes.io/restartedAt":"2026-06-10T12:34:56+09:00"}
```

✅ restart의 정체: template에 annotation을 하나 찍어 "template이 바뀐 척" 해서 롤링 업데이트를 트리거하는 것. 같은 태그 재배포가 필요할 때 씁니다.

## Step 6. DaemonSet — 노드마다 1개

```bash
kubectl apply -f manifests/daemonset.yaml
kubectl get ds node-agent
kubectl get pods -l app=node-agent -o wide
```

예상 출력:
```
NAME         DESIRED   CURRENT   READY   ...   (DESIRED = 노드 수)
node-agent   2         2         2

NAME               ...   NODE
node-agent-aaaaa   ...   ip-192-168-xx-xx...    ← 노드마다 정확히 1개
node-agent-bbbbb   ...   ip-192-168-yy-yy...
```

> 노드를 늘리면(eksctl scale nodegroup) 자동으로 따라 늡니다 — replicas 없는 컨트롤러의 의미.

## 정리

```bash
bash cleanup.sh
```
