# 퀴즈 — 16. Troubleshooting

### Q1. CrashLoopBackOff 상태에서 가장 먼저 봐야 할 정보 두 가지는?

---

### Q2. Exit Code 137 의 두 가지 의미는?

---

### Q3. Pod 가 Pending 인데 노드 자원은 충분한 것 같다. 다음 점검 1순위는?

---

### Q4. Service 호출이 무응답인데 Endpoints 에 IP 가 등록되어 있다. 다음 점검은?

---

### Q5. 노드가 NotReady 인 동안 그 노드의 Pod 들의 상태 변화는?

---

### Q6. PVC 가 `WaitForFirstConsumer` 로 영원히 Pending 일 때 점검 방향은?

---

### Q7. 다음 명령들의 차이는?
```
kubectl logs my-pod
kubectl logs my-pod --previous
kubectl logs my-pod -c my-container
```

---

### Q8. `kubectl describe pod` 의 Events 와 `kubectl get events` 의 차이는?

---

### Q9. 노드 디스크 가득으로 NotReady 가 됐다. 즉시 Pod 빼내는 명령 흐름은?

---

### Q10. (실습 검증) Pod 의 마지막 종료 코드를 한 번에 보는 명령은?

---

## 정답

<details>

**Q1**: `kubectl logs --previous` (직전 인스턴스 로그) + `kubectl describe pod` 의 Last State 섹션 (Reason / Exit Code)
**Q2**: OOMKilled (메모리 limit 초과로 cgroup이 SIGKILL) + 외부 SIGKILL (수동 종료 또는 시스템)
**Q3**: nodeSelector / affinity / taint 매칭 — `kubectl describe pod` 의 Events 의 정확한 메시지
**Q4**: Pod 의 readinessProbe 결과 / 앱 자체 동작 (`kubectl exec ... curl localhost:port`)
**Q5**: 5분 (기본 NodeLease) 후 `Unknown` → 그 후 controller manager 가 새 노드로 Pod 이전 시도
**Q6**: PVC 자체보다 Pod 의 스케줄링 문제. `kubectl describe pod` 로 진짜 원인.
**Q7**:
- `logs my-pod`: 현재 인스턴스의 stdout/stderr
- `--previous`: 직전 종료된 인스턴스의 로그 (CrashLoop 진단용)
- `-c my-container`: 멀티 컨테이너 Pod 의 특정 컨테이너 지정
**Q8**: describe 의 Events 는 그 객체에만 한정. `kubectl get events` 는 전체 NS 의 모든 events.
**Q9**: `kubectl cordon <node>; kubectl drain <node> --ignore-daemonsets --delete-emptydir-data; aws ec2 terminate-instances ...` 또는 `kubectl delete nodeclaim` (Karpenter)
**Q10**: `kubectl get pod <name> -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}'`

</details>

다음 모듈: [17-cost-optimization](../17-cost-optimization/)
