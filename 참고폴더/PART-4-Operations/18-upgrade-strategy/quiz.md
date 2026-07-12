# 퀴즈 — 18. Upgrade Strategy

### Q1. EKS 업그레이드 순서로 옳은 것은?

A. 노드 → Control Plane → Addon
B. Control Plane → Addon → 노드
C. Addon → Control Plane → 노드
D. 동시에

---

### Q2. K8s skew policy: kubelet 버전과 kube-apiserver 의 관계는?

---

### Q3. EKS 한 번에 몇 마이너 버전을 점프할 수 있나?

---

### Q4. EKS Standard support 기간은?

A. 6개월
B. 12개월
C. 14개월
D. 24개월

---

### Q5. Deprecated API 사용 여부 점검 도구 두 가지를 적으세요.

---

### Q6. Managed Node Group 업그레이드의 동작은?

---

### Q7. Karpenter 의 Drift 가 노드 업그레이드에 어떻게 활용되는가?

---

### Q8. PDB 가 너무 빡빡해 노드 업그레이드 stuck 시 해결 방법은?

---

### Q9. Blue/Green 클러스터 업그레이드 패턴의 단점 두 가지는?

---

### Q10. (실습 검증) 현재 클러스터의 Control Plane 과 모든 노드의 K8s 버전을 한 줄로 보는 명령은?

---

## 정답

<details>

**Q1**: B
**Q2**: kubelet ≤ kube-apiserver. 즉 노드 버전이 Control Plane 보다 낮거나 같아야.
**Q3**: 한 번에 한 마이너 버전 (1.30 → 1.31). 두 단계 (1.30 → 1.32) 는 두 번 시행.
**Q4**: C
**Q5**: pluto, EKS Upgrade Insights (콘솔/CLI), kubent, kubectl convert + 검사
**Q6**: 새 launch template (최신 EKS-optimized AMI) 생성 → ASG 가 점진 surge → 옛 노드 cordon/drain → 종료. PDB 존중.
**Q7**: EC2NodeClass 의 AMI alias 가 `al2023@latest` 면 새 AMI 자동 drift → 점진 교체. Disruption Budget 따라 무중단.
**Q8**: PDB 의 minAvailable 임시 완화, 또는 PDB 일시 제거 후 업그레이드 후 복구
**Q9**: 2배 비용 (이행 동안), DNS / 세션 / 데이터(PVC) 마이그 복잡
**Q10**: `kubectl version && kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}={.status.nodeInfo.kubeletVersion}{"\n"}{end}'`

</details>

다음: [pitfalls.md](./pitfalls.md)
