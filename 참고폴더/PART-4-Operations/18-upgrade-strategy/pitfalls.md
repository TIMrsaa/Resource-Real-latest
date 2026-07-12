# 흔한 함정 5선 — 18. Upgrade Strategy

## 1. Addon 업데이트 안 하고 노드 먼저 올림

**증상**: 노드 1.31 인데 vpc-cni / coredns 가 1.29 호환 버전 → 시스템 Pod 에러.

**원인**: 업그레이드 순서 오해.

**해결**: 항상 Control Plane → addon → 노드.

---

## 2. PDB 막혀 노드 업그레이드 영원히 진행 안 됨

**증상**: 한 두 노드는 새 버전인데 나머지가 옛 그대로.

**원인**: PDB `minAvailable: 100%` 또는 같은 효과의 설정.

**진단**:
```bash
kubectl get events --sort-by='.lastTimestamp' | grep -i pdb
kubectl get pdb -A
```

**해결**: 업그레이드 동안 임시 완화 또는 cordon + 수동 drain.

---

## 3. Deprecated API 못 보고 업그레이드 → 워크로드 깨짐

**증상**: 업그레이드 후 일부 Helm release 가 작동 안 함 (`PodDisruptionBudget v1beta1` 같은 예).

**예방**: pluto / EKS Insights 사용.

**복구**:
- 매니페스트 새 API 로 update + 재배포
- 옛 클러스터 백업이 있다면 복원

---

## 4. Karpenter Drift 가 동시에 너무 많이 일어남

**증상**: AMI alias 변경 → 모든 노드가 한꺼번에 drift → 동시 회수로 워크로드 영향.

**원인**: Disruption Budget 미설정.

**해결**:
```yaml
disruption:
  budgets:
    - nodes: "20%"        # 한 번에 20% 만 회수
```

---

## 5. 업그레이드 후 EBS CSI / LB Controller 가 동작 안 함

**증상**: 새 PVC 가 Pending, 새 Ingress 의 ALB 안 만들어짐.

**원인**: Addon (또는 Helm 으로 설치한 controller) 의 IRSA Role 의 OIDC issuer 가 옛 클러스터 ARN 가리킴 (블루/그린 시나리오).

**해결**: 새 클러스터에 맞는 IRSA 재셋업:
```bash
eksctl create iamserviceaccount --override-existing-serviceaccounts ...
```

또는 Helm chart 의 SA annotation 갱신.

---

## 부록 — 업그레이드 체크리스트

- [ ] Control Plane 현재 버전 / 목표 버전 확인
- [ ] EKS Upgrade Insights 통과
- [ ] pluto 로 deprecated API 점검
- [ ] addon 호환 버전 확인
- [ ] PDB 검토 (너무 빡빡한지)
- [ ] (선택) 백업
- [ ] Control Plane 업그레이드 → 검증
- [ ] Addon 업그레이드 → 검증
- [ ] 노드 그룹 업그레이드 → 검증
- [ ] 시나리오 앱 회귀 테스트
- [ ] 다음 분기 업그레이드 준비
