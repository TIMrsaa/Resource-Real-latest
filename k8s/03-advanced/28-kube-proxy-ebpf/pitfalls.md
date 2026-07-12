# 흔한 함정 5선

## 1. 노드의 iptables를 손으로 수정

kube-proxy는 주기적으로 규칙을 재동기화합니다 — 수동 수정은 곧 덮입니다(또는 충돌로 더 꼬입니다). 노드 방화벽이 필요하면 KUBE-* 체인 밖(직접 만든 체인)에서, Pod 레벨은 NetworkPolicy로. "고쳤는데 자꾸 원복되는" 미스터리의 정체.

## 2. conntrack 포화를 앱 문제로 오진

p99만 가끔 튀고 로그에 단서가 없는 간헐 타임아웃 — conntrack count/max를 먼저 보라. 특히 keep-alive 없는 대량 외부 호출, NAT 게이트웨이 뒤의 단명 커넥션 폭주가 주범. 대응: 커넥션 풀(근본), nf_conntrack_max 상향(완화), 타임아웃 튜닝.

## 3. externalTrafficPolicy: Local + 단일 replica

Local은 "Pod 있는 노드만 트래픽 수신"인데, replica 1개면 그 노드 외 전부가 헬스체크 탈락 — LB 용량을 스스로 줄인 셈. Local은 **충분한 replica + 노드 분산(topologySpread)** 과 세트.

## 4. UDP 서비스의 낡은 conntrack 블랙홀

UDP는 핸드셰이크가 없어 백엔드 Pod가 교체돼도 기존 conntrack 엔트리가 옛 IP로 계속 보냅니다 → DNS 등에서 "일부 클라이언트만 한동안 실패". kube-proxy가 stale 엔트리를 지워주지만 엣지 케이스가 남습니다 — UDP 서비스 배포 직후의 간헐 실패는 이걸 의심.

## 5. "느리니까 일단 IPVS/eBPF" 성급한 전환

수백 Service 규모에서 iptables는 병목이 아닙니다 — 전환 비용(운영 지식, 디버깅 도구 교체)이 이득을 넘습니다. 전환의 정량 근거: `sync_proxy_rules_duration` 추세, 규칙 수만 단위, conntrack 아닌 매칭 지연 증거. 측정 없는 세대 교체는 유행 따라가기입니다.

## 실무 사고 사례

> 모바일 게임 런칭일 — 외부 API(결제) 호출이 간헐 2초 타임아웃. 앱/DB/API 서버 다 정상. 사흘 만에 노드 메트릭에서 `nf_conntrack_count`가 max에 붙어 있는 것을 발견 — 결제 SDK가 keep-alive 없이 **요청마다 새 TLS 연결**을 만들고 있었고, TIME_WAIT 엔트리가 테이블을 채웠습니다. 커넥션 풀 적용 + conntrack_max 상향으로 해소. 교훈: **L7 증상(타임아웃)의 범인이 L4 테이블일 수 있습니다.** conntrack 사용률을 노드 대시보드 기본 패널로.
