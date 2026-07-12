# 자가 점검 퀴즈

**Q1.** Service → Pod 트래픽 전달에 관여하는 리소스/컴포넌트를 순서대로 나열하세요.

**Q2.** ClusterIP에 ping이 실패하는데 같은 IP로 curl은 성공합니다. 이유는?

**Q3.** Service 연결이 안 될 때 가장 먼저 확인할 리소스와, 그것이 비어 있을 때의 원인 후보 2가지는?

**Q4.** LoadBalancer 타입을 만들면 함께 생기는 것 2가지(K8s 안)와 1가지(AWS)는?

**Q5.** readiness probe에 실패한 Pod에는 무슨 일이 일어나는가요? (Pod 자체 vs 트래픽 관점)

**Q6.** Service의 분배가 HTTP 요청 단위로 균등하지 않은 근본 이유는?

**Q7.** 클러스터를 삭제하기 전에 LoadBalancer Service를 먼저 지워야 하는 이유는?

---

## 정답

**A1.** Service(selector 선언) → **EndpointSlice**(Ready Pod IP 명단, 컨트롤러가 갱신) → **kube-proxy**(명단을 보고 각 노드에 iptables/IPVS 규칙 설치) → 커널이 DNAT으로 Pod IP에 전달.

**A2.** iptables 규칙이 해당 **TCP 포트에 대해서만** DNAT을 수행하기 때문. ICMP(ping)에 대한 규칙은 없고, ClusterIP 자체는 어떤 장비에도 할당돼 있지 않습니다.

**A3.** `kubectl get endpointslices`. 비어 있으면 ① Service selector와 Pod 라벨 불일치 ② Pod가 Ready 아님(probe 실패/시작 중).

**A4.** K8s 안: **ClusterIP + NodePort** (포함 관계). AWS: **NLB** (cloud controller가 생성, EXTERNAL-IP에 DNS 이름).

**A5.** Pod는 죽지 않고 계속 Running(restart 안 됨 — 그건 liveness). 다만 **EndpointSlice 명단에서 빠져** 트래픽을 받지 않습니다.

**A6.** Service는 **L4(커넥션 단위) 무작위 분배**이기 때문. keep-alive로 커넥션을 유지하면 그 위의 모든 HTTP 요청이 같은 Pod로 갑니다. HTTP 단위 분배는 L7(Ingress/메시)의 영역.

**A7.** NLB는 K8s 컨트롤러가 지웁니다. 클러스터(컨트롤러)를 먼저 죽이면 NLB/보안그룹이 **고아로 남아 과금**되고 VPC 삭제도 막습니다.
