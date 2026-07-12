# 자가 점검 퀴즈

**Q1.** Deployment, ReplicaSet, Pod의 책임을 각각 한 단어~한 구로 구분하세요.

**Q2.** 롤링 업데이트 중 `kubectl get rs`를 치면 RS가 2개 보입니다. 각각 무엇이며, 완료 후 옛 RS는 어떻게 되는가요?

**Q3.** `maxSurge: 0, maxUnavailable: 0` 으로 설정하면 어떤 일이 일어나는가요?

**Q4.** running 중인 Pod에서 selector 대상 라벨을 제거하면 일어나는 일 2가지는?

**Q5.** 같은 이미지 태그로 강제 재배포하는 공식적인 방법과 그 내부 동작은?

**Q6.** 새 버전이 ErrImagePull로 실패 중입니다. 서비스가 멀쩡한 이유와 올바른 복구 명령은?

**Q7.** DaemonSet에 replicas 필드가 없는 이유는?

---

## 정답

**A1.** Deployment = **버전 교체/롤백**, ReplicaSet = **개수 유지**, Pod = **실행 단위**.

**A2.** 옛 버전 RS(줄어드는 중)와 새 버전 RS(늘어나는 중). 완료 후 옛 RS는 삭제되지 않고 **replicas 0으로 보존**됩니다(롤백용, `revisionHistoryLimit`개까지).

**A3.** 업데이트가 **불가능**해집니다 — 더 띄울 수도(surge 0) 줄일 수도(unavailable 0) 없으니 교체할 방법이 없습니다. apply 시 검증 에러로 거부됩니다.

**A4.** ① RS가 부족분을 채우려 **새 Pod 생성** ② 라벨 떼인 Pod는 **고아로 계속 실행** (관리 주체 없음). 합계 Pod 수 +1.

**A5.** `kubectl rollout restart deployment/<name>`. template의 annotation에 `restartedAt` 타임스탬프를 찍어 template 변경으로 인식시켜 정상 롤링 업데이트를 트리거합니다.

**A6.** `maxUnavailable` 제약 때문에 옛 Pod들이 Ready 상태로 유지된 채 첫 교체에서 롤아웃이 정지했기 때문. 복구: `kubectl rollout undo deployment/<name>`. (Deployment 삭제는 서비스 중단을 부릅니다)

**A7.** 개수의 기준이 사용자 지정 수가 아니라 **"대상 노드 수"** 이기 때문. 노드가 늘고 줄면 Pod도 자동으로 따라갑니다.
