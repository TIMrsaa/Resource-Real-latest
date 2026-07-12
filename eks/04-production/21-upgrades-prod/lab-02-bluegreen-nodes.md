# Lab 02 — Blue/Green 노드그룹: 즉시 롤백이 되는 노드 교체

플릿 전략 중 "가장 안전한 칼"을 소규모로 완주합니다 — blue(구) 노드그룹의 워크로드를 green(신)으로 무중단 이주시키고, **롤백 가능 시점**이 어디까지인지 몸으로 확인합니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. blue 세계 구축 — 구형 플릿과 그 위의 워크로드

```bash
eksctl create nodegroup --cluster $CLUSTER --region $AWS_REGION \
  --name blue-lab --nodes 2 --node-type t3.small --node-labels fleet=blue

# 워크로드: PDB를 갖춘 3-replica 앱 (35의 그 모범 세트)
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fleet-app
  labels: { app: fleet-app }
spec:
  replicas: 3
  selector:
    matchLabels: { app: fleet-app }
  template:
    metadata:
      labels: { app: fleet-app }
    spec:
      nodeSelector: { fleet: blue }      # 현역(blue) 함대에만 배치
      containers:
        - name: podinfo
          image: ghcr.io/stefanprodan/podinfo:6.7.1
EOF
cat <<'EOF' | kubectl apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: fleet-app-pdb }
spec:
  maxUnavailable: 1
  selector: { matchLabels: { app: fleet-app } }
EOF
kubectl rollout status deploy/fleet-app
kubectl get pods -l app=fleet-app -o wide    # 전부 blue 노드에
```

> nodeSelector `fleet=blue`는 실험 통제용입니다 — 실제 Blue/Green에선 워크로드가 어느 플릿이든 갈 수 있어야 하므로 이 셀렉터가 **없어야** drain이 이주를 만듭니다. Step 3에서 풉니다.

## Step 2. green 세계 준비 — 실전이라면 여기가 "새 버전"

```bash
eksctl create nodegroup --cluster $CLUSTER --region $AWS_REGION \
  --name green-lab --nodes 2 --node-type t3.small --node-labels fleet=green
kubectl get nodes -L fleet
```

✅ 이 시점의 상태가 Blue/Green의 정수입니다: **두 세계가 공존하고, 아직 아무것도 옮기지 않았습니다.** 실전이라면 여기서 green에 카나리아 Pod를 띄워 새 AMI/버전을 검증합니다 — 유저 트래픽 없이.

## Step 3. 전환 — cordon, 셀렉터 해제, drain

```bash
# ① 워크로드의 blue 고정 해제 (이주 허용)
kubectl patch deploy fleet-app --type=json -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]'
kubectl rollout status deploy/fleet-app    # 이 롤링부터 새 Pod는 아무 데나 — 아직 blue에도 갈 수 있습니다

# ② blue 봉쇄 — 신규 배치 차단 (기존은 그대로)
for n in $(kubectl get nodes -l fleet=blue -o jsonpath='{.items[*].metadata.name}'); do
  kubectl cordon $n
done

# ③ 감시를 걸고 (터미널 2: kubectl get pods -l app=fleet-app -o wide -w)
#    blue를 한 대씩 비웁니다 — PDB의 박자로
for n in $(kubectl get nodes -l fleet=blue -o jsonpath='{.items[*].metadata.name}'); do
  kubectl drain $n --ignore-daemonsets --delete-emptydir-data --timeout=300s
done
kubectl get pods -l app=fleet-app -o wide    # 전부 green 노드에!
```

✅ 이주 완료 — 그리고 **지금이 롤백의 황금 시점**입니다: blue는 cordon됐을 뿐 살아 있습니다. green에서 문제가 보이면 `uncordon blue → cordon green → drain green`으로 즉시 되돌아갑니다. 이 보험이 Blue/Green이 이주 기간의 2배 용량으로 사는 것.

## Step 4. 검증 후 blue 청산 — 보험 해지

```bash
# 실전 체크: 앱 golden signal, 관측 스택(12), (있다면) 부하 스모크(13)
kubectl get pods -l app=fleet-app    # 3/3 Running, 재시작 0

eksctl delete nodegroup --cluster $CLUSTER --region $AWS_REGION --name blue-lab --wait
```

✅ blue 삭제 = 롤백 창 종료. 그래서 실전 runbook은 "green 검증 완료 후 N시간(또는 1영업일) 뒤 blue 삭제"처럼 **보험 기간을 명시**합니다.

## Step 5. 다른 전략과의 자리 비교 (기록)

```markdown
| 방금 한 것(B/G) | 관리형 롤링이었다면 | Karpenter drift였다면 |
|----------------|-------------------|---------------------|
| NG 2개, 수동 전환 | update-nodegroup-version 한 줄 | AMI alias 갱신뿐 |
| 롤백: blue 유지 중 즉시 | 구 AMI 재롤링 (수십 분+) | NodeClass 되돌리면 역drift |
| 비용: 이주 중 2배 | surge 만큼만 | budgets 폭만큼 |
| 적합: 큰 점프·위험 변경 | 정기 패치 | 상시 순환 문화 |
```

## 정리

```bash
bash cleanup.sh    # 잔여 노드그룹·워크로드·PDB
```
