# 흔한 함정 5선 — 19. Prometheus Deep Dive

## 1. Cardinality 폭발로 Prometheus OOM

**증상**: Prometheus Pod 가 자주 OOMKilled, 메모리 사용 급증.

**원인**: 어느 메트릭이 라벨 조합 폭주.

**진단**:
```bash
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=topk(20, count by (__name__)({__name__=~".+"}))'
```

**해결**:
- 문제 메트릭의 라벨 정리 (앱 코드 수정)
- ServiceMonitor 의 metricRelabelings 로 drop
- 메모리 limits 늘리기 (임시방편)

---

## 2. ServiceMonitor 추가했는데 target 미등록

**증상**: Prometheus targets 페이지에 안 나타남.

**원인 후보**:
- ServiceMonitor 의 `release: kps` 라벨 누락
- Service 의 selector 가 Pod 라벨과 안 맞음
- Pod 의 metrics 컨테이너 포트가 Service port 정의와 안 맞음

**진단 순서**:
1. `kubectl get servicemonitor -A`
2. `kubectl get prometheus -n monitoring -o yaml | yq '.items[].spec.serviceMonitorSelector'`
3. `kubectl get endpoints <svc>`
4. Prometheus Operator 로그: `kubectl logs -n monitoring kps-kube-prometheus-stack-operator-xxx`

---

## 3. Prometheus reload 안 된 채로 바뀐 설정 사용

**증상**: ConfigMap / values 변경했는데 효과 없음.

**원인**: Prometheus Operator 가 재구성을 위해 Pod 재시작 또는 reload 필요.

**해결**:
- Prometheus Operator 가 자동 reload 처리 (수 초~수 분)
- 즉시 반영 필요하면 Pod 재시작:
```bash
kubectl rollout restart statefulset prometheus-kps-kube-prometheus-stack-prometheus -n monitoring
```

---

## 4. 디스크 용량 부족 → WAL 깨짐

**증상**: Prometheus Pod 가 시작 못 함, 로그에 `WAL corruption`.

**원인**: PVC 가 가득 차서 WAL 쓸 수 없음. 또는 잘못 종료.

**해결**:
```bash
# PVC 사이즈 확장 (allowVolumeExpansion: true 인 경우)
kubectl patch pvc <pvc> -n monitoring --type=merge \
  -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'

# 또는 retention 짧게
helm upgrade kps prometheus-community/kube-prometheus-stack \
  --reuse-values \
  -n monitoring \
  --set prometheus.prometheusSpec.retention=12h
```

마지막 수단 — WAL 삭제 (데이터 손실):
```bash
kubectl exec -n monitoring prometheus-kps-...-0 -c prometheus -- rm -rf /prometheus/wal
kubectl rollout restart statefulset ...
```

---

## 5. /metrics endpoint 가 응답 안 해서 up=0

**증상**: Prometheus 의 `up` 메트릭이 0, 그러나 Pod 자체는 Running.

**원인 후보**:
- 컨테이너의 metrics 포트와 Service 의 targetPort 불일치
- 앱이 metrics 핸들러를 등록 안 함
- 앱이 5xx 응답
- network policy 가 Prometheus 의 접근 차단

**진단**:
```bash
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].ports}'

# Pod 내부에서 직접 호출
kubectl exec <pod> -- wget -qO- localhost:9090/metrics | head
```
