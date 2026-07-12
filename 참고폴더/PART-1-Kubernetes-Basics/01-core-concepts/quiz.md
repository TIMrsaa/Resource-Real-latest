# 퀴즈 — 01. 핵심 개념

각 문제에 답하고, 정답을 보기 전에 직접 손으로 명령을 실행해 검증해 보세요.

---

### Q1. Pod와 컨테이너의 관계로 옳은 것은?

A. Pod는 컨테이너 그 자체다
B. Pod는 1개 이상의 컨테이너를 묶고, 같은 IP/볼륨을 공유한다
C. Pod 안의 컨테이너들은 서로 다른 노드에 분산될 수 있다
D. Pod는 노드보다 큰 단위다

---

### Q2. 다음 중 **클러스터-스코프** 인 리소스는?

A. Pod
B. Service
C. PersistentVolume
D. ConfigMap

---

### Q3. ReplicaSet을 직접 만들지 않고 Deployment를 쓰는 이유 두 가지를 적으세요.

---

### Q4. 다음 명령을 실행했을 때, 어떤 일이 벌어지나?

```bash
kubectl set image deploy/web nginx=nginx:1.28
```

A. 기존 Pod 내부에서 컨테이너 이미지를 hot-swap 한다
B. 새 ReplicaSet이 생기고, 기존 ReplicaSet의 Pod들이 점진적으로 교체된다
C. Deployment가 즉시 모든 Pod를 죽이고 새 이미지로 다시 만든다
D. 변화 없음 (재기동 필요)

---

### Q5. `default` Namespace의 Service `db` 를 다른 NS의 Pod에서 호출하는 FQDN은?

A. `db.svc.default.cluster.local`
B. `db.default.svc.cluster.local`
C. `db.cluster.local`
D. `default.db.svc.local`

---

### Q6. 다음 strategy 설정의 의미를 한 줄로 설명하세요.

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 0
    maxUnavailable: 1
```

---

### Q7. `kubectl rollout undo deploy/web` 은 내부적으로 무엇을 하는가?

A. ReplicaSet의 spec을 롤백 시점으로 되돌린다
B. 새 ReplicaSet을 만들고 거기서 새 Pod를 띄운다
C. 이전 ReplicaSet의 replicas를 늘리고 현재 ReplicaSet의 replicas를 줄인다
D. 모든 Pod를 동시에 재기동한다

---

### Q8. Pod가 `Pending` 상태에 머물러 있을 때 가장 먼저 확인할 명령은?

A. `kubectl logs <pod>`
B. `kubectl exec -it <pod> -- sh`
C. `kubectl describe pod <pod>` 의 Events 섹션
D. 노드 SSH로 직접 들어가 `docker ps`

---

### Q9. 다음 중 Namespace에 의해 격리되지 **않는** 것은?

A. RBAC의 Role
B. ResourceQuota
C. ClusterRole
D. NetworkPolicy

---

### Q10. (실습) `lab-team-x` NS를 만들고, 거기에 `web` Deployment(replicas=2, image=nginx)를 배포한 뒤, 다음 명령으로 어느 노드에 떠 있는지 확인하는 한 줄 명령은?

---

## 정답

<details>
<summary>펼쳐서 보기</summary>

**Q1**: B
**Q2**: C — Pod, Service, ConfigMap은 NS-scoped, PersistentVolume은 cluster-scoped
**Q3**: 롤링 업데이트, 롤백, 버전 이력 관리, 선언적 갱신 (이 중 두 가지)
**Q4**: B — 새 ReplicaSet 생성 + 점진 교체
**Q5**: B — `<svc>.<ns>.svc.cluster.local`
**Q6**: 평소 replicas의 1개까지는 모자라도 되지만, 평소보다 많아지지는 않는다 (= 노드 자원이 빠듯할 때 적합한 안전 옵션)
**Q7**: C — 이전 ReplicaSet의 replicas를 회복시키는 방식
**Q8**: C — Events에 스케줄링 실패/이미지 pull 실패 등이 기록됨
**Q9**: C — ClusterRole은 cluster-scoped
**Q10**: `kubectl create ns lab-team-x && kubectl create deploy web --image=nginx --replicas=2 -n lab-team-x && kubectl get pods -n lab-team-x -o wide`

</details>

다음: [pitfalls.md](./pitfalls.md)
