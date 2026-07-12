# 흔한 함정 5선 — 11. Karpenter Advanced

## 1. Spot 회수가 자주 일어나서 워크로드 불안정

**증상**: Pod 이 자주 NotReady, 노드 수가 출렁임.

**원인**: 단일/소수 인스턴스 family 만 허용 → 그 시점에 capacity 부족인 family 가 회수.

**해결**:
- `instance-family` 최소 5~10개로 다양화
- `instance-cpu` 도 다양 (`["2","4","8","16"]`)
- AZ 3개 모두 허용
- 중요 워크로드는 PDB + 별도 ondemand NodePool

---

## 2. PDB 가 너무 빡빡해 Drift 가 영원히 진행 안 됨

**증상**: EC2NodeClass 변경 후 며칠 지나도 노드 교체 안 됨.

**진단**:
```bash
kubectl get nodeclaims -L karpenter.sh/drifted
# 모두 Drifted 표시되어 있는데 안 회수
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=50 | grep -i 'budget\|pdb'
```

**원인**: `minAvailable: 100%` 같은 PDB.

**해결**:
- PDB 를 `minAvailable: 80%` 같은 현실적 값으로
- Disruption Budget `nodes: "20%"` 와 균형

---

## 3. ondemand fallback 이 작동 안 함

**증상**: Spot 못 받아서 Pod 가 Pending 인데 ondemand NodePool 에서 노드 안 나옴.

**원인 후보**:
- ondemand NodePool 의 requirements 가 Pod nodeSelector 와 호환 안 됨
- ondemand NodePool 의 limits 가 너무 작음
- weight 설정 누락

**진단**:
```bash
kubectl describe nodepool ondemand
kubectl get pods -o wide | grep Pending
# Pod 의 events
kubectl describe pod <pending>
```

흔한 메시지: `requirements not satisfied` — Pod 의 affinity 와 NodePool 의 requirements 가 안 맞음.

---

## 4. Drift 후 Pod 이 잠시 Pending

**증상**: EC2NodeClass 변경 후 짧은 시간 동안 Pod 가 Pending.

**원인**: Karpenter 가 새 spec 노드를 만드는 동안 시간 갭. Disruption Budget 이 작으면 더 길어짐.

**해결**:
- 매니페스트 변경을 트래픽 적은 시간에
- Schedule budget 으로 업무 시간 보호
- 또는 변경 전 Pod replicas 늘려두기 (여유 capacity)

---

## 5. 가격이 갑자기 비싸짐

**증상**: Cost Explorer 에서 EC2 비용 폭증.

**원인 후보**:
- Spot 부족 → ondemand 로 fallback (Spot 비활성화한 NodePool 만 살아있음)
- consolidationPolicy 가 너무 보수적이라 빈 노드 안 사라짐
- requests > 실제 사용 → over-provisioning

**진단**:
```bash
# Spot 노드 vs OD 노드 비율
kubectl get nodes -L capacity-type | awk '{print $NF}' | sort | uniq -c

# 빈 노드 있는지
kubectl describe nodes | grep -A5 'Allocated resources'

# 워크로드 사용률 (Container Insights / Prometheus)
```

**해결**:
- NodePool 다양화 강화
- consolidationPolicy 를 `WhenEmptyOrUnderutilized` 로
- Pod requests 재조정 (VPA 사용 가능)
