# 자가 점검 퀴즈

**Q1.** NetworkPolicy의 허용 모델을 RBAC와 비교해 설명하세요.

**Q2.** ns 전체 ingress 기본 거부 정책의 YAML 핵심 2줄은?

**Q3.** "monitoring ns의 app=prometheus Pod에서만" 허용하려 합니다. AND가 되는 from 구조를 쓰라.

**Q4.** egress 정책 적용 후 "IP로는 되는데 이름으로 안 된다". 원인과 수정은?

**Q5.** api→db(5432) ingress만 허용했습니다. db의 응답 패킷을 위한 egress 규칙이 필요한가?

**Q6.** 정책의 ports에 Service 포트와 컨테이너 포트 중 무엇을 적는가요? 이유는?

**Q7.** 정책을 다 만들었는데 아무것도 차단되지 않습니다. 가장 먼저 의심할 것은? (EKS 기준 확인 명령 포함)

---

## 정답

**A1.** 둘 다 **deny 규칙이 없는 화이트리스트** 모델. RBAC는 "어떤 Binding에도 안 걸리면 거부", NetworkPolicy는 "정책에 선택되는 순간 허용 합집합 외 거부"(선택 안 되면 전부 허용이라는 점이 차이).

**A2.** `podSelector: {}` (모든 Pod 선택) + `policyTypes: [Ingress]` (ingress 통제 모드, 허용 규칙 없음).

**A3.**
```yaml
from:
- namespaceSelector:
    matchLabels: { kubernetes.io/metadata.name: monitoring }
  podSelector:
    matchLabels: { app: prometheus }
```
(두 셀렉터가 **한 항목** 안 — `-`가 하나)

**A4.** egress 통제가 kube-dns로의 질의(53)까지 차단한 것. kube-dns Pod로의 UDP/TCP 53 허용 egress 규칙을 추가합니다.

**A5.** 불필요 — NetworkPolicy는 **stateful**(연결 추적)이라 허용된 연결의 응답은 자동 허용됩니다. 새로운 연결의 방향만 정책 대상.

**A6.** **컨테이너(Pod) 포트.** 정책 검사는 Service의 DNAT 이후 Pod에 도달하는 시점 기준이기 때문.

**A7.** CNI가 정책을 집행하지 않는 상태. EKS: `aws eks describe-addon --addon-name vpc-cni ... ` 의 configuration에서 `enableNetworkPolicy` 확인 + `kubectl get pods -n kube-system -l k8s-app=aws-node`에 nodeagent 컨테이너 존재 확인.
