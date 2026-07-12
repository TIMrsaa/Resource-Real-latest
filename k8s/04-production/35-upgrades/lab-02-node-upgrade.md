# Lab 02 — 노드 무중단 교체: drain, 데드락, 그리고 자동화

> control plane 업그레이드는 실습하지 않습니다 — 공유 클러스터에서 비가역이고 수십 분이 걸립니다. 대신 그 다음 단계이자 **우리 손에 남는 유일한 무중단 기술**, drain 기반 노드 교체를 처음부터 끝까지 수행합니다.

## Step 1. 출발 상태

lab-01의 ha-app(3 replicas, PDB maxUnavailable=1)이 어디에 있는지:

```bash
kubectl get pods -l app=ha-app -o wide
NODES=($(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'))
TARGET=${NODES[0]}
echo "교체(비우기) 대상: $TARGET"
```

## Step 2. cordon — 문만 닫기

```bash
kubectl cordon $TARGET
kubectl get node $TARGET     # Ready,SchedulingDisabled
kubectl get pods -l app=ha-app -o wide   # 기존 Pod은 그대로!
```

✅ cordon = `spec.unschedulable=true` — **신규만 차단**하고 기존은 건드리지 않습니다. "지금부터 이 노드에 새 살림 금지"라는 준비 선언.

## Step 3. drain — PDB의 박자에 맞춰 비우기

터미널을 하나 더 열어 감시를 걸고:

```bash
# 터미널 1 — 축출과 재생성의 안무 관찰
kubectl get pods -l app=ha-app -o wide -w
```

```bash
# 터미널 2 — 실행
kubectl drain $TARGET --ignore-daemonsets --delete-emptydir-data --timeout=180s
```

터미널 1에서 볼 것:

```
ha-app-aaa  Terminating          ← TARGET에 있던 것 (eviction 승인됨)
ha-app-ddd  Pending → Running    ← 다른 노드에서 대체 기동
(대체가 Ready가 된 뒤에야 다음 축출 — PDB가 박자를 만듭니다)
```

검증 두 가지:

```bash
# ① drain 내내 Ready 개수가 2 밑으로 안 떨어졌는가 (PDB의 약속)
kubectl get pdb ha-app-pdb          # ALLOWED DISRUPTIONS로 잔여 한도 확인
# ② TARGET에는 DaemonSet(aws-node, kube-proxy)만 남았는가
kubectl get pods -A -o wide --field-selector spec.nodeName=$TARGET
```

✅ delete가 아니라 **eviction**이라서 가능한 광경입니다 — API 서버가 PDB를 보고 축출을 거부/승인합니다(theory §5). 이 상태의 노드는 이제 안전하게 종료·교체할 수 있습니다.

## Step 4. 데드락 재현 — 브레이크가 꽉 잠기면

PDB를 일부러 최악으로: minAvailable = replicas.

```bash
kubectl uncordon $TARGET
kubectl patch pdb ha-app-pdb --type=json \
  -p='[{"op":"remove","path":"/spec/maxUnavailable"},{"op":"add","path":"/spec/minAvailable","value":3}]'
kubectl get pdb ha-app-pdb          # ALLOWED DISRUPTIONS: 0 ← lab-01 Step 4의 그 "후보"

# ha-app이 있는 아무 노드나 drain 시도
VICTIM=$(kubectl get pods -l app=ha-app -o jsonpath='{.items[0].spec.nodeName}')
kubectl drain $VICTIM --ignore-daemonsets --delete-emptydir-data --timeout=30s
```

예상:

```
error when evicting pods/"ha-app-..." ... Cannot evict pod as it would violate the pod's disruption budget.
(재시도 반복 → 30초 후 timeout 실패)
```

✅ **"업그레이드가 몇 시간째 안 끝나요"의 가장 흔한 정체**를 직접 봤습니다. 관리형 노드그룹이라면 이 상태가 UPDATE 실패로 뜹니다. 진단 명령은 하나 — `kubectl get pdb -A`에서 ALLOWED DISRUPTIONS=0 찾기. 복구:

```bash
kubectl patch pdb ha-app-pdb --type=json \
  -p='[{"op":"remove","path":"/spec/minAvailable"},{"op":"add","path":"/spec/maxUnavailable","value":1}]'
kubectl uncordon $VICTIM 2>/dev/null || true
```

## Step 5. 실전에선 이걸 EKS가 해줍니다 — 명령만 확보

```bash
aws eks describe-nodegroup --cluster-name k8s-study --nodegroup-name workers \
  --region ap-northeast-2 --query 'nodegroup.{version:version,releaseVersion:releaseVersion,maxUnavailable:updateConfig}' 2>/dev/null

# 실행은 하지 않습니다 (10~20분 + 공유 클러스터). 형태만:
# aws eks update-nodegroup-version --cluster-name k8s-study --nodegroup-name workers --region ap-northeast-2
#   → 새 AMI 노드 추가 → 구 노드 cordon+drain(우리가 방금 한 그것, PDB 존중) → 종료 — 롤링 자동화
#   → updateConfig.maxUnavailable로 Step 3~4의 "동시에 몇 노드" 조절
```

✅ 자동화가 하는 일이 Step 2~3과 동일함을 아는 것 — 그래서 자동화가 멈추면(Step 4) 우리가 원인을 짚을 수 있습니다.

## Step 6. runbook 완성 (산출물)

```markdown
# 업그레이드 runbook (분기 반복용)
0. lab-01 게이트 G1~G5 전부 통과 — 아니면 중단
1. control plane: update-cluster-version (비가역, 1 마이너, EKS 무중단)
2. 애드온: G3에서 확보한 default 버전으로 (eks 11 절차)
3. 노드: update-nodegroup-version — 감시 항목: PDB ALLOWED DISRUPTIONS,
   Pending 적체, 앱 golden signal
4. 검증: 워크로드 헬스 → 관측 스택 헬스 → insights 재조회
막힘 대응: get pdb -A로 0건 색출 → replicas/PDB 조정 → 재개
롤백: 노드는 구 AMI 재롤링 / CP는 불가 — 그래서 0번이 전부
```

## 정리

```bash
bash cleanup.sh
```
