# 자가 점검 퀴즈

**Q1.** LB Controller의 watch 대상 3가지와 각각 만들어지는 실물은?

**Q2.** instance vs ip 타겟의 패킷 경로 차이와, ip가 EKS 정석인 이유 3가지는?

**Q3.** ip 모드에서 컨트롤러가 타겟 목록을 유지하는 원천과 readiness의 역할은?

**Q4.** group.name의 효과와 위험(공유 운명체) — 각각 한 문장으로.

**Q5.** "Ingress를 만들었는데 ADDRESS가 안 생긴다" — 진단 1순위는?

**Q6.** 콘솔에서 ALB 리스너 규칙을 고치면 일어나는 일과 그 원리는?

**Q7.** TargetGroupBinding의 용도와 실무 시나리오는?

**Q8.** 롤링 업데이트 때 ALB 간헐 502의 메커니즘과 처방 2가지는?

---

## 정답

**A1.** ① Ingress(class alb) → ALB+리스너+규칙+대상그룹 ② Service(type LoadBalancer+어노테이션) → NLB+대상그룹 ③ TargetGroupBinding → 기존 대상그룹에 Pod 등록만.

**A2.** instance: ALB→노드 NodePort→kube-proxy 체인→Pod(홉+1, SNAT). ip: ALB→Pod IP 직행. 정석인 이유: ① 홉/지연 감소 ② 헬스체크가 Pod 단위(readiness 정합) ③ Fargate 호환(+externalTrafficPolicy 문제 소멸). 전제는 VPC CNI의 "Pod IP=VPC IP"(07).

**A3.** **EndpointSlice**(k8s 05)를 watch — ready인 Pod IP를 대상그룹에 등록, 빠지면 draining→제거. 즉 readiness(k8s 14)가 ALB 트래픽 수신 여부를 직접 결정합니다.

**A4.** 효과: 여러 Ingress를 ALB 하나의 규칙들로 통합 — LB 비용을 N→1로. 위험: 그룹은 ALB 설정을 공유하므로 한 Ingress의 잘못된 어노테이션/충돌이 그룹 전체에 영향 — 공유 시 거버넌스(admission 제한) 필요.

**A5.** 컨트롤러 로그(`kubectl logs -n kube-system deploy/aws-load-balancer-controller`)에서 AccessDenied/검증 에러 확인 — 권한(IRSA/Pod Identity) 부족이 최다 원인. Ingress 이벤트보다 컨트롤러 로그가 원문입니다.

**A6.** 수십 초 내 컨트롤러가 원래대로 재생성 — reconcile 루프(k8s 30)가 K8s 객체(진실)와 실물의 diff를 수렴시키기 때문. 변경은 Ingress/어노테이션으로만.

**A7.** LB/대상그룹을 다른 체계(Terraform/인프라팀)가 소유할 때, K8s는 그 대상그룹에 Pod IP 등록/해제만 담당. 시나리오: 인프라팀이 LB(보안/도메인/WAF)를 통제하고 앱팀이 백엔드 연결을 셀프서비스.

**A8.** 종료 Pod이 대상그룹에서 빠지기(전파) 전에 SIGTERM으로 연결을 끊어 그 사이 도착한 요청이 502. 처방: ① preStop sleep으로 등록 해제 전파 시간 확보(k8s 14) ② deregistration delay/헬스체크-readiness 경로 정렬(+pod readiness gate 활용).
