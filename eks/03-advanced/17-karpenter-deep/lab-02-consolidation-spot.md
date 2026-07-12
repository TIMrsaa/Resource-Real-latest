# Lab 02 — 되감기(consolidation) 관찰과 통제, 그리고 Spot

만드는 것만 자동이면 반쪽입니다 — 줄어드는 쪽(consolidation)을 관찰하고, 그것을 **멈추는 세 가지 손잡이**(do-not-disrupt, budgets, policy)를 돌려봅니다. 마지막으로 Spot을 섞습니다.

전제: lab-01의 NodePool `lab` + inflate(4 replicas, 2xlarge급 1대).

## Step 1. replace 관찰 — 큰 노드가 작은 노드로

4개 중 3개를 줄이면, 8 vCPU 노드에 1 vCPU Pod 하나 — 명백한 과잉입니다:

```bash
kubectl scale deploy inflate --replicas=1
kubectl get nodeclaims -w
```

예상 (consolidateAfter: 1m 후):

```
NAME         TYPE          ...   ← 기존 2xlarge급
lab-xxxxx    c7i.large     ...   ← 더 싼 새 노드 등장 (replace!)
(기존 NodeClaim 삭제 — Pod는 새 노드로 이동)
```

```bash
kubectl get nodeclaim -o wide     # 남은 것이 large급 하나인지
kubectl get pods -l app=inflate -o wide
```

✅ **delete가 아니라 replace** — "Pod 1개는 large면 충분"을 시뮬레이션으로 알아내고, 새 노드를 먼저 띄운 뒤 옮기고 큰 것을 회수했습니다. 이동은 eviction 경유 — PDB가 있었다면 존중됐을 것(35의 안전망이 여기서도).

## Step 2. 손잡이 ① — do-not-disrupt: "이 Pod는 건드리지 마"

```bash
kubectl patch deploy inflate --type=strategic -p \
  '{"spec":{"template":{"metadata":{"annotations":{"karpenter.sh/do-not-disrupt":"true"}}}}}'
kubectl rollout status deploy/inflate
kubectl scale deploy inflate --replicas=4 && sleep 90 && kubectl scale deploy inflate --replicas=1
kubectl get nodeclaims -w    # 2분 넘게 관찰
```

예상: 과잉 노드가 생겨도 **consolidation이 일어나지 않습니다** — do-not-disrupt Pod가 올라탄 노드는 자발적 중단 금지. 배치 작업·GPU 학습(19)의 보호막입니다. 확인 후 해제:

```bash
kubectl patch deploy inflate --type=strategic -p \
  '{"spec":{"template":{"metadata":{"annotations":{"karpenter.sh/do-not-disrupt":null}}}}}'
```

## Step 3. 손잡이 ② — budgets: 조직의 시간표를 강제

"교체는 좋지만 지금은 안 돼"를 선언하는 법:

```bash
# 전면 금지 (nodes: "0") — 장애 대응 중·이벤트 중 얼려두기
kubectl patch nodepool lab --type=merge -p \
  '{"spec":{"disruption":{"budgets":[{"nodes":"0"}]}}}'
kubectl get nodepool lab -o jsonpath='{.spec.disruption.budgets}'; echo
# (과잉 상태를 만들어도 회수 없음을 확인해보세요)

# 원복 — "동시 1대까지"
kubectl patch nodepool lab --type=merge -p \
  '{"spec":{"disruption":{"budgets":[{"nodes":"1"}]}}}'
```

✅ budgets는 **비율/개수 + (선택) 스케줄**로 선언합니다 — "평일 야간에만 10%" 같은 조직 규칙이 YAML이 됩니다.

## Step 4. Spot 혼합 — 요금제를 계산에 맡기기

```bash
kubectl patch nodepool lab --type=json -p '[
  { "op": "replace",
    "path": "/spec/template/spec/requirements/3",
    "value": { "key": "karpenter.sh/capacity-type", "operator": "In", "values": ["spot", "on-demand"] } }
]'
# 새 노드 유도 (기존 노드 교체를 위해 replicas 왕복)
kubectl scale deploy inflate --replicas=4; sleep 120
kubectl get nodeclaims -o wide    # CAPACITY 열: spot이 골라졌는가요?
```

예상: 새 NodeClaim의 capacity-type이 **spot** — 후보만 열어주면 가격 계산이 알아서 고릅니다(price-capacity-optimized, theory §5). 중단 대비는 이미 되어 있습니다: lab-01 Step 1의 SQS 큐가 2분 경고를 받아 cordon+drain을 자동 수행합니다.

```bash
# spot 노드의 표식
kubectl get nodes -l karpenter.sh/capacity-type=spot
```

## Step 5. 설계 워크시트 (산출물)

```markdown
# NodePool 설계 — 우리 클러스터
## 풀 목록
| 풀 | requirements(요지) | capacity | taint | limits | 용도 |
|----|-------------------|----------|-------|--------|------|
| general | c/m/r 5세대+, amd64+arm64 | spot,od | 없음 | cpu 200 | 무상태 대부분 |
| critical | 동일 | od만 | 없음 | cpu 50 | 중단 민감 (weight로 우선?) |
| team-gpu | g 계열 | od | gpu=true | gpu 8 | 19에서 설계 |
## 규칙
- do-not-disrupt: 배치/마이그레이션 Job 템플릿에 기본 포함
- budgets: 평시 10% / 이벤트 기간 "0" (변경은 PR로 — 39 GitOps)
- expireAfter 720h = AMI 순환 (35의 노드 업그레이드가 이 풀에선 상시 진행형)
- IP 예산(16) 체크: 노드 급증 시나리오에서 min(AZ) 잔여 확인
```

## 정리

```bash
bash cleanup.sh    # NodePool 삭제 → 노드 회수 확인까지
```
