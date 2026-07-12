# 흔한 함정 5선 — 17. Cost Optimization

## 1. Cost Explorer 의 데이터 갱신 지연

**증상**: 어제 자원을 정리했는데 오늘 비용에 반영 안 됨.

**원인**: Cost Explorer 는 24시간 지연. 대시보드 데이터 갱신은 매일 일정 시각.

**해결**:
- 즉시 확인이 필요하면 CloudTrail / EC2 콘솔 직접
- AWS Cost & Usage Reports (CUR) 의 raw 데이터로 빠른 분석

---

## 2. 태그 활성화 안 해서 분리 추적 안 됨

**증상**: 리소스에 태그 붙였는데 Cost Explorer 에 그 태그로 그룹화 옵션이 안 보임.

**원인**: Billing → Cost allocation tags 에서 그 태그를 활성화 안 함.

**해결**:
1. Console → Billing → Cost allocation tags
2. User-Defined 탭에서 `Project`, `Team` 등 활성화
3. **24시간 후** Cost Explorer 에서 사용 가능 (즉시 X)

---

## 3. VPA Auto 모드로 운영 Pod 재시작 폭주

**증상**: VPA 적용 후 Pod 들이 자주 재시작되어 트래픽 영향.

**원인**: Auto 모드는 추천 변경마다 Pod 재시작.

**해결**:
- 운영은 `updateMode: Initial` (Pod 생성 시에만) 또는 `Off` (추천만)
- VPA 의 minReplicas 옵션으로 동시 재시작 제한
- PDB 와 함께 사용

---

## 4. KubeCost / OpenCost 가 비용을 0 으로 표시

**증상**: 모든 리소스의 cost 가 0 또는 누락.

**원인 후보**:
- AWS 가격 정보 못 가져옴 (네트워크 / IAM)
- Prometheus 연결 실패 — 메트릭 없음
- region 설정 안 함

**진단**:
```bash
kubectl logs -n opencost deploy/opencost -c opencost
# "ERROR: failed to query prometheus" 등
```

**해결**: Prometheus URL 정확히, region/cluster 명시:
```bash
helm upgrade opencost ... \
  --set opencost.exporter.defaultRegion=ap-northeast-2 \
  --set opencost.prometheus.external.url=http://<prom>:9090
```

---

## 5. Reserved Instance / Savings Plans 미사용

**증상**: On-Demand 비용이 높음에도 RI/SP 안 씀.

**원인**: 학습/PoC 클러스터는 ON-DEMAND OK 지만 운영은 1년 commit RI/SP 가 30~50% 절감.

**해결**:
- 안정적 Baseline 워크로드 → Compute Savings Plan
- Variable / Burst → Spot
- 둘 조합:
  - Baseline (3대) → SP/On-Demand
  - Burst (Karpenter) → Spot

> **EKS Pod 자체에는 SP 적용 안됨**. EC2 인스턴스에 적용 → 노드 그룹의 평균 사용률에 비례.
