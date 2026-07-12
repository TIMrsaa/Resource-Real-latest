# 퀴즈 — 02. Service & Networking

### Q1. ClusterIP가 실제 네트워크 인터페이스에 존재하지 않는데 어떻게 라우팅되는가?

A. CoreDNS가 패킷을 직접 처리
B. kube-proxy가 노드의 iptables/ipvs 룰로 DNAT
C. CNI 플러그인이 네트워크 카드에 IP 할당
D. EKS Control Plane이 중간에서 프록시

---

### Q2. NodePort 범위는?

A. 1024 ~ 65535
B. 8000 ~ 9000
C. 30000 ~ 32767
D. 자유롭게 지정

---

### Q3. AWS EKS에서 type=LoadBalancer Service를 만들면 기본적으로 만들어지는 LB 종류는? (어노테이션 없을 때)

A. ALB (Application Load Balancer)
B. NLB (Network Load Balancer)
C. CLB (Classic Load Balancer)
D. 만들어지지 않음

---

### Q4. Service `api` 가 NS `prod` 에 있을 때, NS `dev` 의 Pod에서 호출하기 위한 짧은 이름은?

A. `api`
B. `api.dev`
C. `api.prod`
D. 짧은 이름은 불가능, FQDN만 사용

---

### Q5. Endpoints 리소스가 비어있는 (`<none>`) 흔한 원인 두 가지를 적으세요.

---

### Q6. Ingress 리소스를 만들었는데 외부에서 접속이 안 됩니다. 가장 먼저 점검할 것은?

A. CoreDNS Pod 상태
B. Ingress Controller가 클러스터에 설치되어 있는지
C. kube-proxy 상태
D. Service의 nodePort 범위

---

### Q7. CoreDNS가 외부 도메인 `google.com` 을 어떻게 해석할까?

A. CoreDNS가 자체적으로 인터넷의 root 서버까지 재귀 조회
B. CoreDNS는 외부 도메인을 모름, 노드의 외부 DNS로 forward
C. EKS Control Plane이 처리
D. kube-proxy가 처리

---

### Q8. ndots:5 옵션이 외부 도메인 조회 성능에 미치는 영향은?

---

### Q9. Service의 `selector` 를 빈 값으로 두면 어떻게 되는가?

A. 모든 Pod에 매칭됨
B. 어떤 Pod에도 매칭 안 됨, Endpoints 비어있음
C. 자동으로 라벨 추론
D. 에러

---

### Q10. (실습 검증) `web` Deployment(replicas=3) 에 ClusterIP Service를 붙이고, 부하 분산이 라운드 로빈에 가깝게 동작하는지 확인하는 한 줄 명령은?

---

## 정답

<details>
<summary>펼쳐서 보기</summary>

**Q1**: B — kube-proxy가 iptables/ipvs DNAT
**Q2**: C — 30000 ~ 32767
**Q3**: C — CLB (어노테이션 없으면 in-tree CCM이 CLB 생성. AWS LB Controller + 어노테이션 시 NLB)
**Q4**: D — 다른 NS면 FQDN 또는 최소 `api.prod` 형태 필요. `api.dev` 는 dev NS의 api를 찾음
**Q5**: 셀렉터와 Pod 라벨 불일치 / 셀렉터에 매칭되는 Pod가 Ready 가 아님 / Pod 자체가 없음
**Q6**: B — Ingress 리소스만으로는 아무 일도 안 일어남, Controller가 필요
**Q7**: B — `forward . /etc/resolv.conf` 로 노드 외부 DNS에 위임
**Q8**: 점이 적은 외부 도메인은 search 도메인부터 시도하므로 NXDOMAIN 응답 후 절대 도메인 조회 → 1회 추가 쿼리 발생
**Q9**: B
**Q10**: `kubectl run -it --rm dbg --image=alpine -- sh -c 'apk add -q curl && for i in $(seq 1 6); do curl -s http://web/; done'`

</details>

다음: [pitfalls.md](./pitfalls.md)
