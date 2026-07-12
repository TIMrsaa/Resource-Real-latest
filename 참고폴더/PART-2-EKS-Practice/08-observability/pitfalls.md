# 흔한 함정 5선 — 08. Observability

## 1. CloudWatch Logs 비용 폭탄

**증상**: 1주일 만에 $30~$100 청구.

**원인**: 모든 컨테이너 stdout/stderr 가 무필터로 전송. 디버그/스팸 로그까지 누적.

**해결**:
- 앱 로그 레벨 INFO 이상으로 (DEBUG 끄기)
- Fluent Bit 설정에서 namespace 필터 (kube-system 같은 시끄러운 NS 제외)
- Log Group retention 짧게 (`aws logs put-retention-policy --log-group-name ... --retention-in-days 7`)
- 비용 알람 설정

```bash
# 큰 Log Group 찾기
aws logs describe-log-groups \
  --query 'logGroups[].[logGroupName, storedBytes]' --output text \
  | sort -k2 -n | tail
```

---

## 2. Prometheus 디스크 가득

**증상**: Prometheus Pod이 OOM 또는 PVC full.

**원인**:
- retention 너무 김 + cardinality 폭증 (라벨 많은 메트릭)
- 큰 클러스터에 10Gi 디스크 부족

**해결**:
```bash
# 가장 cardinality 높은 메트릭 찾기 (Prometheus UI > Status > TSDB Status)
# 또는 Helm values 변경
helm upgrade kps prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --reuse-values \
  --set prometheus.prometheusSpec.retention=12h \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=20Gi
```

PVC 크기 변경은 EBS volume expansion 필요 (`allowVolumeExpansion: true` StorageClass).

---

## 3. ServiceMonitor 만들었는데 메트릭이 안 잡힘

**증상**: Prometheus targets 페이지에 새 ServiceMonitor 가 안 나타남.

**원인**:
- ServiceMonitor 의 라벨이 Prometheus 가 select 하는 라벨과 불일치
- kube-prometheus-stack 은 기본적으로 `release: <release-name>` 라벨이 있는 ServiceMonitor 만 select

**진단**:
```bash
kubectl get prometheus -n monitoring -o yaml | yq '.items[].spec.serviceMonitorSelector'
# matchLabels: release: kps  ← 이걸 ServiceMonitor 가 가져야 함

kubectl get servicemonitor my-monitor -o yaml | yq '.metadata.labels'
```

**해결**: ServiceMonitor 에 `labels.release: kps` 추가.

또는 모든 ServiceMonitor 를 select 하도록 변경:
```yaml
prometheus:
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    serviceMonitorSelector: {}
```

---

## 4. Grafana 비밀번호 분실

**증상**: 설정 후 admin 비밀번호 잊음.

**해결**:
```bash
kubectl get secret -n monitoring kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

또는 reset:
```bash
kubectl exec -n monitoring deploy/kps-grafana -c grafana -- \
  grafana-cli admin reset-admin-password new-password
```

---

## 5. node-exporter 가 일부 노드에 안 떠있음

**증상**: 일부 노드의 메트릭이 비어있음.

**원인**:
- node-exporter DaemonSet 의 nodeSelector / tolerations 가 일부 노드를 제외
- Spot 노드의 라벨에 매칭 안 됨

**진단**:
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus-node-exporter -o wide
# 모든 노드에 1개씩 떠있어야 함

kubectl get nodes
# 노드 수와 비교
```

**해결**: DaemonSet의 tolerations 에 `operator: Exists` (모든 taint 허용) 추가:
```yaml
prometheus-node-exporter:
  tolerations:
    - operator: Exists
```
