# 퀴즈 — 11. Karpenter Advanced

### Q1. Spot 회수율을 줄이는 가장 효과적인 방법은?

A. 큰 인스턴스 타입 사용
B. 다중 인스턴스 family + 다중 AZ
C. Spot 가격 입찰 상한 설정
D. On-Demand 만 사용

---

### Q2. NodePool 의 weight 차이로 만드는 패턴은?

A. Spot 우선 / On-Demand fallback
B. AZ 분산
C. Drift 제어
D. PDB 적용

---

### Q3. EC2NodeClass 의 spec 변경 시 Karpenter 가 자동으로 하는 것은?

---

### Q4. Disruption Budget 의 schedule 옵션의 형식은?

---

### Q5. Spot 노드 하나가 회수 통지를 받으면 Karpenter 가 하는 일 3가지는?

---

### Q6. NodePool 의 `expireAfter: 168h` 의 효과는?

---

### Q7. 두 NodePool 이 같은 Pod 을 받을 수 있을 때 우선순위 결정은?

A. NodePool 의 weight 만
B. weight + Spot 가격 + 가용성
C. 알파벳 순
D. 무작위

---

### Q8. PDB `minAvailable: 100%` 의 효과는 (Karpenter 입장에서)?

---

### Q9. Karpenter 의 Drift 가 일으키는 노드 교체는 무중단인가? 어떻게?

---

### Q10. (실습 검증) Karpenter 가 만든 노드의 시간당 평균 Spot 비용을 한 줄로 계산하는 방법 (대략적)?

---

## 정답

<details>

**Q1**: B
**Q2**: A
**Q3**: 기존 노드를 Drifted 마크 → Disruption Budget 따라 점진적 교체
**Q4**: cron 형식 (예: `"0 9 * * mon-fri"`) + duration
**Q5**: 노드 cordon (새 Pod 차단) → drain (기존 Pod 우아 이전) → 다른 노드 미리 만듦
**Q6**: 168시간(7일) 후 노드를 강제 회전 — 보안 패치/AMI 업데이트 자동 반영
**Q7**: B
**Q8**: 모든 Pod 가 Ready 여야 disruption 가능 → 사실상 영원히 회수 못 함 → 유지보수 차단
**Q9**: 무중단. Karpenter 가 새 spec 노드를 먼저 만들고 Pod 을 그쪽으로 옮긴 뒤 옛 노드 회수 (PDB 존중)
**Q10**: `kubectl get nodes -l managed-by=karpenter -o jsonpath='{range .items[*]}{.metadata.labels.node\.kubernetes\.io/instance-type}{"\n"}{end}'` 의 각 type 에 대해 `aws ec2 describe-spot-price-history --instance-types` 호출

</details>

다음: [pitfalls.md](./pitfalls.md)
