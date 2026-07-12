# 흔한 함정 5선

## 1. 집행자 없는 정책 (조용한 무효)

NetworkPolicy는 만들어지고 `kubectl get netpol`에도 보이지만, CNI가 집행하지 않으면 **아무 효과 없이 성공한 척**합니다. 보안 감사에서 "정책 있음"으로 체크되고 실제론 다 뚫린 최악의 상태. 도입 시 반드시 차단 테스트로 검증 (lab-01 Step 2 방식).

## 2. DNS egress 누락

lab-02에서 체험한 그것. egress를 켜는 순간 DNS(53/UDP·TCP) 허용 조각이 없으면 모든 이름 기반 통신이 죽습니다. 증상의 시그니처: "IP로는 되는데 이름으로 안 됨".

## 3. AND/OR `-` 위치 실수

`namespaceSelector`와 `podSelector`를 한 항목(AND)으로 쓰려다 별개 항목(OR)으로 써서 의도보다 **훨씬 넓게** 열리는 사고 — "monitoring ns의 prometheus만"이 "monitoring 전체 + 모든 ns의 prometheus"가 됩니다. 정책 리뷰 1순위 체크포인트.

## 4. 포트를 Service 포트로 적음

정책 검사는 DNAT 이후 — 즉 **Pod(컨테이너) 포트** 기준입니다. Service의 80을 적으면 실제 8080 트래픽이 차단됩니다. targetPort를 적는다고 기억하세요.

## 5. 빅뱅 도입 — 전 ns에 한 번에 기본 거부

운영 클러스터에 default-deny를 일괄 배포하면 파악 못 한 통신(모니터링 수집, 웹훅, DNS 캐시)이 동시 다발로 끊깁니다. 점진 도입: ① 신규/저위험 ns부터 ② 통신 그래프를 먼저 관측(VPC Flow Logs, Hubble) ③ allow-same-namespace 완충 정책으로 시작해 좁혀가기.

## 실무 사고 사례

> 보안 점검 후 "egress 통제"를 일괄 적용한 팀. DNS는 챙겼지만 **kubelet의 probe는 챙길 필요가 없다는 걸 몰라서** 혼란이 왔습니다 — probe는 노드에서 직접 오므로 정책의 영향을 안 받는데, 같은 시간대에 우연히 난 probe 실패를 정책 탓으로 오인해 정책 전체를 롤백했습니다. 진짜 원인은 무관한 배포였습니다. 교훈: **정책 적용 전후로 "무엇이 영향권인지"를 정확히 알아야 합니다** — NetworkPolicy는 Pod 간 트래픽에만 작용하고, 노드→Pod(kubelet probe)는 영향권 밖입니다.
