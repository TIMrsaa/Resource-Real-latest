# 퀴즈 — 03. Config & Storage

### Q1. ConfigMap을 환경변수로 주입한 후, ConfigMap의 값을 변경했습니다. 환경변수에 즉시 반영되는가?

A. 네, 자동 반영
B. 아니오, Pod 재시작 필요
C. kubectl rollout restart 시에만
D. 30초 대기 후 자동 반영

---

### Q2. Secret을 매니페스트의 `data:` 필드에 평문으로 적으면 어떻게 되는가?

A. 자동으로 base64 인코딩
B. 에러
C. 그대로 저장 (보안 위험)
D. 자동으로 암호화

---

### Q3. PVC의 accessModes 중 EBS가 지원하는 것은?

A. ReadOnlyMany
B. ReadWriteOnce
C. ReadWriteMany
D. 모두 지원

---

### Q4. `volumeBindingMode: WaitForFirstConsumer` 가 해결하는 문제는?

---

### Q5. StatefulSet의 Pod가 종료될 때 순서는?

A. 동시에
B. 순차 (0 → 1 → 2)
C. 역순 (2 → 1 → 0)
D. 임의

---

### Q6. StatefulSet의 `volumeClaimTemplates` 으로 만들어진 PVC는 StatefulSet 삭제 시 어떻게 되는가?

A. 함께 삭제됨
B. 남아있음 (수동 삭제 필요)
C. PV는 삭제, PVC는 남음
D. reclaimPolicy 에 따라 다름

---

### Q7. Headless Service (`clusterIP: None`) 가 일반 Service와 다른 점은?

---

### Q8. ConfigMap을 파일로 마운트한 경우, 값이 바뀌면 약 몇 초 후 갱신되는가?

A. 즉시
B. 약 30초 ~ 1분
C. 약 5분
D. Pod 재시작 전까지 안 바뀜

---

### Q9. Secret을 매니페스트에 `data:` 가 아니라 `stringData:` 로 적으면 차이점은?

---

### Q10. (실습) `data-redis-0` PVC만 삭제하지 않고 다른 모든 redis 관련 리소스를 삭제하려면?

---

## 정답

<details>

**Q1**: B
**Q2**: B — `data` 필드는 base64 인코딩된 문자열만 허용. 평문이면 invalid.
**Q3**: B — EBS는 RWO만. 다중 노드 공유는 EFS/FSx 사용.
**Q4**: PVC가 만들어진 직후 PV/EBS를 만들지 않고 Pod 스케줄 시점에 만들어, Pod가 배치된 노드의 AZ에 EBS 생성 → AZ 미스매치 회피
**Q5**: C — 역순
**Q6**: B — 데이터 보존 위해 자동 삭제 안 함
**Q7**: ClusterIP를 만들지 않고, Pod별 DNS A 레코드를 직접 노출 → StatefulSet의 안정된 ID에 활용
**Q8**: B
**Q9**: `stringData` 는 평문으로 적으면 K8s가 자동 base64 인코딩해 `data` 필드로 변환. 작성 편의용.
**Q10**: `kubectl delete sts/redis svc/redis-hl && kubectl delete pvc -l app=redis --field-selector metadata.name!=data-redis-0`

</details>

다음: [pitfalls.md](./pitfalls.md)
