# 자가 점검 퀴즈

**Q1.** etcd에 직접 읽고 쓸 수 있는 컴포넌트를 모두 나열하세요.

**Q2.** kube-scheduler가 Pod를 위해 하는 일을 정확히 한 문장으로. ("실행한다"는 단어를 쓰면 오답)

**Q3.** Pod가 `Pending` 상태에 머물러 있습니다. 어떤 컴포넌트(들)를 의심해야 하고, 첫 확인 명령은?

**Q4.** control plane 전체가 5분간 다운되면 (a) 기존 서비스 트래픽 (b) 신규 배포 (c) 죽은 Pod 자동 복구 — 각각 어떻게 되는가요?

**Q5.** `kubectl get nodes`에 control plane 노드가 안 보이는 이유는? (EKS 기준)

**Q6.** "조정 루프(reconciliation loop)"의 3단계를 쓰고, ReplicaSet 컨트롤러를 예로 들어 설명하세요.

**Q7.** kubelet은 왜 `kubectl get pods -n kube-system`에 안 나오는가요?

---

## 정답

**A1.** **kube-apiserver 하나뿐.** 스케줄러, 컨트롤러 매니저, kubelet 전부 API 서버를 경유합니다.

**A2.** nodeName이 비어 있는 Pod를 watch하다가, Filtering/Scoring으로 최적 노드를 골라 **Pod의 `spec.nodeName` 필드에 그 이름을 기록합니다.** (실행은 kubelet의 일)

**A3.** 스케줄러 단계 또는 그 이전 문제. 첫 명령: `kubectl describe pod <name>` (Events 섹션의 `FailedScheduling` 메시지에 자원 부족/taint 등 이유가 적혀 있음).

**A4.** (a) 정상 유지 — kube-proxy 규칙과 컨테이너는 그대로. (b) 불가 — API 서버가 없으니 주문 접수 불가. (c) 불가 — Node/ReplicaSet 컨트롤러가 못 움직임. 5분 뒤 복구되면 밀린 조정이 일괄 수행됩니다.

**A5.** control plane은 AWS 소유 인프라에서 돌고, 우리 클러스터에는 Node 객체로 등록되지 않기 때문. 우리가 받는 것은 API 엔드포인트 URL뿐.

**A6.** ① 현재 상태 관찰(watch) ② 원하는 상태(spec)와 비교 ③ 차이를 메꾸는 행동. ReplicaSet 컨트롤러: 자기 selector에 맞는 Pod 수를 세고(①), `replicas: 3`과 비교해(②), 부족하면 Pod 생성 / 초과면 삭제 API 호출(③).

**A7.** kubelet은 Pod가 아니라 **노드 OS의 systemd 프로세스**입니다. Pod를 띄우는 주체이므로 자신이 Pod일 수 없습니다 (닭과 달걀 문제).
