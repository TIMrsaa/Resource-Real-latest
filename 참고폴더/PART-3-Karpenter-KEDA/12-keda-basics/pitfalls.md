# 흔한 함정 5선 — 12. KEDA Basics

## 1. ScaledObject 적용 후 HPA 가 안 만들어짐

**증상**: `kubectl get hpa` 비어있음.

**원인**:
- KEDA Operator 죽었거나 RBAC 부족
- ScaledObject 에 syntax 오류 (`metadata` vs `parameters` 혼동)

**진단**:
```bash
kubectl describe scaledobject <name>     # status / events
kubectl logs -n keda -l app=keda-operator --tail=30
```

---

## 2. CPU/Memory trigger 가 metrics-server 없어 작동 안 함

**증상**: ScaledObject 만들었지만 메트릭 `<unknown>`.

**원인**: CPU/Memory trigger 는 K8s metrics-server 의존.

**해결**:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

EKS 의 일부 환경:
```bash
kubectl patch deploy metrics-server -n kube-system --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

---

## 3. Prometheus trigger 의 PromQL 결과가 NaN 일 때

**증상**: scale 이 일어나지 않음. Prometheus UI 에서 쿼리해보면 결과 없음.

**원인**:
- 메트릭 이름 오타
- ServiceMonitor 가 등록 안 되어 메트릭이 Prometheus 에 없음
- 라벨 selector 오타

**진단**:
```bash
# Prometheus 직접 쿼리
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090
curl -sG 'http://localhost:9090/api/v1/query' --data-urlencode 'query=<YOUR_QUERY>' | jq

# KEDA Operator 로그
kubectl logs -n keda -l app=keda-operator --tail=50 | grep -i 'prometheus\|trigger'
```

KEDA 는 NaN 을 0 으로 처리 → 임계 미만 → scale down. 디버깅이 필요한 이유.

---

## 4. scale-to-zero 후 첫 요청이 늦어짐 (cold start)

**증상**: Pod 0 에서 1 로 올라가는 동안 (수십초 ~ 1분) 트래픽 처리 못 함.

**원인**: Pod 시작 시간 (이미지 pull + readinessProbe).

**완화**:
- `minReplicaCount: 1` 로 (scale-to-zero 포기)
- 이미지 작게 (distroless, scratch)
- 노드 워밍 (Karpenter 의 inflate Pod 으로 capacity 미리 확보)
- Knative / OpenFunction 같은 hot-pool 솔루션 (KEDA 단독으론 어려움)

---

## 5. KEDA 가 자동 생성한 HPA 를 수동 변경

**증상**: `keda-hpa-*` 의 maxReplicas 를 직접 수정했는데 30초 후 KEDA 가 다시 덮어씀.

**원인**: KEDA 가 ScaledObject 의 spec 으로 HPA 를 reconcile. 직접 변경은 무시됨.

**해결**: 변경은 **ScaledObject 에서**:
```bash
kubectl edit scaledobject <name>
# spec.maxReplicaCount 등 수정
```
