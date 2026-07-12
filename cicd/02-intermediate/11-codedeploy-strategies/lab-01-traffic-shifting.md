# Lab 01 — 트래픽 전환을 눈으로: 가중치가 옮겨갑니다

배포 전략의 본질(가중치 전환)을 실제로 관찰합니다. 무거운 ECS 대신 **k8s에서 트래픽 분할**을 구현해 개념을 빠르게 체득하고(공유 클러스터 활용), CodeDeploy 구성은 개념+CLI로 확인합니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. 두 버전 배포 (v1·v2)

```bash
kubectl create ns deploylab
for v in v1 v2; do
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: app-$v, namespace: deploylab }
spec:
  replicas: 4
  selector: { matchLabels: { app: myapp, version: $v } }
  template:
    metadata: { labels: { app: myapp, version: $v } }
    spec:
      containers:
      - name: app
        image: ghcr.io/stefanprodan/podinfo:6.7.1
        env: [{ name: PODINFO_UI_MESSAGE, value: "$v" }]
        ports: [{ containerPort: 9898 }]
EOF
done
kubectl -n deploylab expose deploy app-v1 --name=app --port=80 --target-port=9898 \
  --selector='app=myapp' 2>/dev/null || \
kubectl -n deploylab create service clusterip app --tcp=80:9898 && \
kubectl -n deploylab patch service app -p '{"spec":{"selector":{"app":"myapp"}}}'
kubectl -n deploylab rollout status deploy/app-v1
kubectl -n deploylab rollout status deploy/app-v2
```

## Step 2. 롤링의 본질 — replica 수가 곧 가중치

Service가 `app=myapp`으로 두 버전을 다 고르므로, **replica 비율이 트래픽 비율**이 됩니다(theory §1):

```bash
# 현재 8개(v1:4, v2:4) → 50/50
kubectl run probe -n deploylab --rm -i --restart=Never --image=curlimages/curl -- sh -c \
  'for i in $(seq 1 40); do curl -s http://app/ | grep -o "\"message\": \"v[12]\""; done | sort | uniq -c'
```

예상: v1 약 20, v2 약 20. 이제 **카나리처럼** v2를 5%로:

```bash
kubectl -n deploylab scale deploy app-v1 --replicas=19
kubectl -n deploylab scale deploy app-v2 --replicas=1     # 1/20 = 5%
kubectl -n deploylab rollout status deploy/app-v1
kubectl run probe -n deploylab --rm -i --restart=Never --image=curlimages/curl -- sh -c \
  'for i in $(seq 1 60); do curl -s http://app/ | grep -o "v[12]"; done | sort | uniq -c'
```

예상: v2가 약 5%. ✅ **replica 조작으로 카나리를 흉내** 냈습니다 — 그런데 이건 조잡합니다(정확한 %가 안 되고, 관찰 게이트도 없습니다). theory §4가 말한 "네이티브 카나리의 부재"를 몸으로 느끼는 지점. 17의 Argo Rollouts가 이걸 정밀하게 만듭니다.

## Step 3. 확대 — "관찰 후" (수동으로 게이트 흉내)

```bash
# 5%에서 "오류율을 관찰"했다고 치고 (실제로는 eks 12·13의 지표)
echo "관찰: v2의 오류율/지연이 정상인가요? (여기서 사람이 판단 — 17에서 자동화)"
kubectl -n deploylab scale deploy app-v2 --replicas=5   # 25%
sleep 5
kubectl -n deploylab scale deploy app-v2 --replicas=20  # 100%
kubectl -n deploylab scale deploy app-v1 --replicas=0   # 구버전 철수
kubectl run probe -n deploylab --rm -i --restart=Never --image=curlimages/curl -- sh -c \
  'for i in $(seq 1 30); do curl -s http://app/ | grep -o "v[12]"; done | sort | uniq -c'
```

✅ 전환 완료 — 그런데 각 단계의 "관찰"이 **사람의 판단**이었습니다. 이것이 자동화돼야 진짜 progressive delivery입니다(17).

## Step 4. 블루/그린 — 스위치 전환

카나리와 달리 블루/그린은 **한 번에** 전환합니다. Service selector를 버전으로 못박아 구현:

```bash
# 지금 다시 v1(blue)만 서빙하도록
kubectl -n deploylab scale deploy app-v1 --replicas=4
kubectl -n deploylab scale deploy app-v2 --replicas=4
kubectl -n deploylab patch service app -p '{"spec":{"selector":{"app":"myapp","version":"v1"}}}'
kubectl run probe -n deploylab --rm -i --restart=Never --image=curlimages/curl -- sh -c \
  'for i in $(seq 1 10); do curl -s http://app/ | grep -o "v[12]"; done | sort | uniq -c'   # 전부 v1

echo "=== 스위치! (green으로 한 번에) ==="
kubectl -n deploylab patch service app -p '{"spec":{"selector":{"app":"myapp","version":"v2"}}}'
kubectl run probe -n deploylab --rm -i --restart=Never --image=curlimages/curl -- sh -c \
  'for i in $(seq 1 10); do curl -s http://app/ | grep -o "v[12]"; done | sort | uniq -c'   # 전부 v2
```

✅ **selector 한 줄이 전체 트래픽을 옮겼습니다** — 블루/그린의 스위치. 롤백도 selector를 v1로 되돌리면 **즉시**(구 환경이 살아 있으니). 대가는 두 버전을 동시에 띄우는 비용(01의 "일시 2배").

## Step 5. CodeDeploy 구성 확인 (개념 + CLI)

ECS/Lambda라면 같은 것을 CodeDeploy가 자동화합니다. 배포 구성을 조회:

```bash
aws deploy list-deployment-configs --region $AWS_REGION \
  --query 'deploymentConfigsList[?contains(@, `Canary`) || contains(@, `Linear`) || contains(@, `AllAtOnce`)]' --output json | head
```

예상: `CodeDeployDefault.ECSCanary10Percent5Minutes`, `...LinearEvery1Minute`, `...AllAtOnce` 등. ✅ 우리가 손으로 한 가중치 전환을 CodeDeploy는 **배포 구성 이름 하나**로 합니다 — 그리고 다음 랩에서 자동 롤백까지 붙입니다.

```markdown
# 전략 매핑 (내가 확인한 것)
| 전략 | 이 랩의 구현 | CodeDeploy | k8s 실전 |
|------|------------|-----------|----------|
| 롤링 | replica 비율 | (EC2) | Deployment 기본 |
| 카나리 | replica 조작(조잡) | ECSCanary10Percent5Minutes | 17 Rollouts |
| 블루/그린 | selector 전환 | ECS blue/green(ALB 리스너) | 17 Rollouts / 수동 |
```

## 정리

deploylab은 lab-02에서 롤백·마이그레이션에 사용.
