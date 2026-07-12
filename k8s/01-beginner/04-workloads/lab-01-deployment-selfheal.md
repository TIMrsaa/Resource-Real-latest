# Lab 01 — Deployment 생성과 자가 치유 파괴 실험

## Step 1. 3단 구조 확인

```bash
kubectl apply -f manifests/deployment.yaml
kubectl get deploy,rs,pods -l app=web
```

예상 출력:
```
NAME                  READY   UP-TO-DATE   AVAILABLE
deployment.apps/web   3/3     3            3

NAME                            DESIRED   CURRENT   READY
replicaset.apps/web-7d4b9c8f6   3         3         3      ← Deployment가 만든 RS

NAME                      READY   STATUS    RESTARTS
pod/web-7d4b9c8f6-abcde   1/1     Running   0          ← RS가 만든 Pod들
pod/web-7d4b9c8f6-fghij   1/1     Running   0
pod/web-7d4b9c8f6-klmno   1/1     Running   0
```

✅ 이름에 계보가 보입니다: `web`(Deploy) → `web-7d4b9c8f6`(RS, template 해시) → `web-7d4b9c8f6-abcde`(Pod).

```bash
# 소유 관계 증명
kubectl get pod -l app=web -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}{"\n"}'
# → ReplicaSet (Deployment가 아닙니다! Pod의 부모는 RS)
```

## Step 2. 파괴 실험 ① — Pod 죽이기

터미널 1: `kubectl get pods -l app=web -w`

터미널 2:
```bash
VICTIM=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod $VICTIM
```

터미널 1 예상 출력:
```
web-7d4b9c8f6-abcde   1/1     Terminating   ...
web-7d4b9c8f6-xyz99   0/1     Pending       ...   ← 거의 동시에 대체자 생성!
web-7d4b9c8f6-xyz99   1/1     Running       ...
```

✅ RS 컨트롤러의 조정 루프가 "3개여야 하는데 2개"를 감지하고 즉시 채웠습니다. **삭제가 곧 복구 훈련**인 시스템.

## Step 3. 파괴 실험 ② — 라벨 떼기 (고아 만들기)

```bash
TARGET=$(kubectl get pods -l app=web -o jsonpath='{.items[0].metadata.name}')
kubectl label pod $TARGET app-           # app 라벨 제거
kubectl get pods --show-labels | grep -E "NAME|web"
```

예상 출력:
```
web-7d4b9c8f6-fghij   1/1   Running   ...   pod-template-hash=7d4b9c8f6     ← 고아 (app 라벨 없음)
web-7d4b9c8f6-klmno   1/1   Running   ...   app=web,pod-template-hash=...
web-7d4b9c8f6-xyz99   1/1   Running   ...   app=web,pod-template-hash=...
web-7d4b9c8f6-new11   1/1   Running   ...   app=web,pod-template-hash=...   ← 새로 생긴 대체자
```

✅ **검증 포인트**: Pod는 4개가 됐습니다! RS는 라벨로만 세상을 보므로 "3개 → 2개"로 인식해 하나 더 만들었고, 라벨 떼인 Pod는 **아무도 관리하지 않는 고아**로 계속 돕니다.

> 💡 실무 활용: 이 동작은 버그가 아니라 기능입니다 — 문제 있는 Pod를 라벨만 떼서 **서비스에서 격리한 채 부검(post-mortem)** 하는 기법으로 씁니다.

```bash
kubectl delete pod $TARGET    # 고아 수동 정리
```

## Step 4. 스케일

```bash
kubectl scale deployment web --replicas=5
kubectl get pods -l app=web --no-headers | wc -l     # → 5
kubectl scale deployment web --replicas=3
```

> HPA(모듈 13)가 하는 일이 본질적으로 이 scale 명령의 자동화입니다.

## Step 5. 파괴 실험 ③ — 노드 하나가 사라진다면 (관찰만)

```bash
kubectl get pods -l app=web -o wide    # Pod들이 어느 노드에 있는지 기록
```

노드 장애 시나리오: 노드가 NotReady가 되면 Node 컨트롤러가 기본 **5분**(tolerationSeconds) 후 그 노드의 Pod를 축출하고, RS가 다른 노드에 재생성합니다. 즉 노드 장애 복구의 기본값은 "5분 안에 자동" — 더 빠르게 하려면? 모듈 12(taint 기반 축출 튜닝)에서.

## 트러블슈팅

| 증상 | 원인/해결 |
|------|----------|
| `selector does not match template labels` | selector.matchLabels와 template.metadata.labels 불일치 — apply 자체가 거부됨 |
| Pod가 Pending | 노드 자원 부족 — `kubectl describe pod`로 확인, replicas 줄이기 |
| 삭제했는데 계속 살아남 | 그게 정상입니다(자가 치유). 진짜 끄려면 Pod가 아니라 **Deployment를** 지워라 |

## 정리

다음 lab에서 이어서 쓰므로 그대로 둡니다.
