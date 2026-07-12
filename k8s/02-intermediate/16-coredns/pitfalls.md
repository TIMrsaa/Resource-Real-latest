# 흔한 함정 5선

## 1. 외부 API 라이브러리의 타임아웃 = DNS 5회 질의 비용

HTTP 클라이언트 타임아웃을 1초로 잡았는데 DNS 확장 질의(최대 5회 × 왕복)만으로 그걸 소진 — "외부 API가 느려요"의 숨은 범인. FQDN/ndots 조정 후 p99가 극적으로 떨어지는 사례가 흔합니다.

## 2. CoreDNS replicas를 기본 2로 방치한 채 클러스터 확장

노드 100대, Pod 3000개가 돼도 CoreDNS는 여전히 2개 — 질의 폭주 시 drop/지연. 대응: replicas 증설(노드 수에 비례), 캐시 TTL 상향, NodeLocal DNSCache(모듈 37). CoreDNS의 CPU/메모리와 `coredns_dns_requests_total` 메트릭을 관측 대상에 포함하세요.

## 3. ConfigMap 직접 수정 → 애드온 업그레이드 때 증발

EKS의 coredns는 관리형 애드온 — Corefile을 ConfigMap으로 직접 고치면 업그레이드 시 기본값으로 덮입니다. "사내 도메인 분기가 어느 날 사라졌어요". 운영 변경은 애드온 configuration values로.

## 4. dnsPolicy: Default의 오해

이름만 보면 "기본값" 같지만 실제 기본은 ClusterFirst입니다. Default는 **노드의 resolv.conf 상속** = 클러스터 내부 이름이 안 풀립니다. hostNetwork Pod에서 내부 이름이 안 풀리면 `ClusterFirstWithHostNet`을 깜빡한 것.

## 5. DNS 캐싱 없는 언어 런타임

자바를 제외한 다수 런타임(Go 기본, Python requests 등)은 자체 DNS 캐시가 없습니다 — 매 요청마다 질의. 초당 수백 호출이면 CoreDNS에 초당 수백(×ndots 증폭) 질의. 대응: 커넥션 풀/keep-alive(질의 자체를 줄임), NodeLocal DNSCache, 클라이언트 캐시 도입.

## 실무 사고 사례

> 트래픽 피크마다 전 서비스 레이턴시가 출렁이는데 CPU/메모리는 멀쩡 — 3주를 헤맨 끝에 CoreDNS 메트릭에서 질의 drop을 발견. 원인은 ① 외부 결제 API를 초당 500회 호출(케이스 1: ndots 5배 증폭) ② keep-alive 미사용으로 매 호출 DNS 질의(케이스 5). FQDN 적용 + 커넥션 풀로 CoreDNS 질의량 1/8로, 레이턴시 출렁임 소멸. 교훈: **"전부 조금씩 느려진다"는 공유 인프라(DNS) 신호입니다. CoreDNS 메트릭을 대시보드에 상시 노출하세요.**
