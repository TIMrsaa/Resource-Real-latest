# 흔한 함정 5선

## 1. 커널 버전 요구를 확인하지 않고 도입

Cilium의 기능은 커널 버전에 따라 켜지고 꺼집니다 — kube-proxy 대체·socket LB·대역폭 관리·일부 L7 기능은 각각 다른 최소 커널을 요구합니다(4.19대부터 5.x대까지). 관리형 K8s(EKS·GKE)의 노드 이미지가 그 커널을 갖는지 확인하지 않고 `kubeProxyReplacement=true`를 켜면 조용히 폴백되거나 기능이 안 켜집니다(그리고 "Cilium 깔았는데 왜 빠르지 않지"의 미궁). `cilium status`의 KubeProxyReplacement 항목과 각 기능의 활성 여부를 반드시 확인하고, 노드 이미지 업그레이드를 도입 계획에 넣어라. 04의 "eBPF 열풍에 검증 없이 올라타기"가 여기서 커널 버전 문제로 구체화됩니다.

## 2. 전 서비스에 L7 정책을 걸어 eBPF 이점을 버림

L3/L4 정책은 순수 eBPF로 커널에서 판정되지만, L7 정책(HTTP 메서드·경로)은 트래픽을 노드의 Envoy 프록시로 우회시킵니다 — 지연이 늘고 CPU를 쓰며 Envoy가 새 장애 지점이 됩니다(lab-02 Step 5). "이왕이면 다 L7으로 촘촘히"는 Cilium을 도입한 이유(성능)를 스스로 무너뜨리는 것입니다. L7 정책은 실제로 HTTP 단위 통제가 필요한 소수 엔드포인트에만, 나머지는 L3/L4로. eBPF의 빠른 경로와 Envoy의 느린 경로를 구분하는 것이 성능 설계의 핵심입니다.

## 3. eBPF 데이터 경로를 iptables 도구로 디버깅

"패킷이 안 통한다"에 `iptables -L`을 실행하면 거의 비어 있습니다 — 라우팅·NAT·정책이 전부 eBPF 맵에 있기 때문입니다(lab-01 Step 4에서 확인). Cilium 디버깅은 다른 도구를 요구합니다: `cilium-dbg bpf lb list`(Service), `cilium-dbg bpf ipcache list`(identity), `cilium-dbg endpoint list`, `cilium-dbg bpf policy get <ep>`, 그리고 `hubble observe`. 이 도구 학습이 도입 비용의 일부이고, 팀이 iptables 지식만으로 운영하려 하면 장애 대응이 마비됩니다. 온보딩에 Cilium 디버깅 실습을 넣어라.

## 4. "하나가 다 한다"의 통합 리스크를 간과

Cilium은 CNI + kube-proxy 대체 + 정책 + 관찰 + (부분) 메시를 한 컴포넌트로 합니다 — 강력하지만, cilium-agent가 문제를 겪으면 여러 층이 **동시에** 영향을 받습니다(네트워크 + Service 라우팅 + 정책 집행이 한꺼번에). 그리고 데이터 경로 업그레이드는 노드 롤링이며 맵·정책 마이그레이션 검증이 필요합니다. PodDisruptionBudget, 노드별 롤링, 업그레이드 전 카나리(일부 노드)와 Hubble 드롭 모니터링이 필수입니다. 통합의 편의에는 "단일 컴포넌트의 폭발 반경"이라는 대가가 붙어 있습니다.

## 5. NetworkPolicy 집행을 실측하지 않고 신뢰

04의 사고 사례(Flannel이 정책을 조용히 무시)는 Cilium에서도 다른 형태로 재현될 수 있습니다 — 정책의 selector가 의도한 Pod를 못 잡거나(라벨 오타), egress를 깜빡해 DNS가 막히거나(toFQDNs를 쓰면서 kube-dns egress를 안 열어줌), default-deny로 전환하며 필수 트래픽을 함께 차단하거나. **정책은 생성이 아니라 실측으로 검증합니다**: 허용 경로는 통과하고 그 외는 `hubble observe --verdict DROPPED`에 잡히는지. `hubble_drop_total{reason="policy_denied"}`을 알람으로 걸면 "집행이 살아 있다"와 "의도치 않은 차단"을 동시에 감시합니다.

## 실무 사고 사례

> 한 회사가 iptables 기반 CNI에서 Cilium으로 이전했습니다 — Service가 4,000개를 넘으며 kube-proxy의 iptables 규칙 갱신이 배포마다 수십 초씩 걸렸고, eBPF의 O(1) 라우팅이 답이었습니다. 이전은 성공적이었고 배포 지연이 사라졌습니다. 그런데 한 달 뒤, 보안팀이 default-deny 네트워크 정책을 전사에 적용하기로 했습니다 — Cilium이니 L7까지 촘촘히, 모든 네임스페이스에 CiliumNetworkPolicy로 HTTP 경로 단위 통제를 걸었습니다. 스테이징에서는 완벽했습니다. 프로덕션 적용 후 몇 시간, p99 지연이 전반적으로 상승했고 일부 서비스는 CPU가 2배가 됐습니다. 원인은 L7 정책이었습니다 — 수백 개 엔드포인트의 트래픽이 전부 노드의 Envoy를 경유하기 시작했고, Envoy의 파싱·판정 오버헤드와 추가 홉이 누적된 것입니다. 정작 L7 통제가 실제로 필요한 서비스는 결제·인증 등 소수였는데, "이왕이면 다"로 전 서비스에 건 것이 화근이었습니다. 더 나쁜 것: 어느 서비스가 왜 느린지 파악하는 데 팀이 헤맸습니다 — iptables 시절의 디버깅 습관으로는 Envoy 경유 여부가 안 보였고, `cilium-dbg`와 Hubble의 L7 플로우를 읽을 줄 아는 사람이 두 명뿐이었습니다. 개선은 두 가지였습니다: ① L7 정책을 실제 필요한 ~20개 엔드포인트로 축소하고 나머지는 L3/L4로 — 지연이 원상 복구됐습니다. ② 팀 전체에 Cilium 데이터 경로·Hubble 디버깅 교육, 그리고 `hubble_http_requests_total`와 Envoy 경유 여부를 대시보드에. 회고 문장이 이 모듈의 요지였습니다: "우리는 eBPF의 빠른 길을 사놓고 절반의 트래픽을 느린 길(Envoy)로 보내고 있었습니다 — **도구의 성능은 그것을 어느 경로로 쓰느냐가 정합니다.**"
