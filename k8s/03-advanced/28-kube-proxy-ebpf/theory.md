# 이론 — kube-proxy의 4세대: iptables → IPVS → nftables → eBPF

> **🌱 17세 눈높이 비유: 콜센터 자동 연결 시스템의 진화**
> 대표번호(ClusterIP)로 걸려온 전화를 상담사(Pod)에게 돌리는 방식의 진화사:
> - **iptables** = 종이 매뉴얼: "대표번호 A는 주사위를 굴려 1/3이면 상담사1..." — 매뉴얼이 수천 장이 되면 찾는 데 오래 걸리고, 상담사 명단이 바뀔 때마다 전체 재인쇄.
> - **IPVS** = 전용 교환기 장비: 명단을 색인(해시)으로 관리 — 수만 명도 즉시.
> - **eBPF** = 전화기 자체에 내장된 칩: 교환대까지 갈 필요도 없이 발신 단계에서 연결.
> 공통의 조력자 **conntrack** = "이 통화는 원래 대표번호로 걸려온 것"을 기억하는 통화 기록부 — 답신이 올바른 번호로 보이게 합니다.

---

## 1. iptables 모드 해부 (EKS 기본)

### 체인 3계층

```
PREROUTING/OUTPUT
  → KUBE-SERVICES                          # 목차: 모든 ClusterIP:port 매칭 줄
      -d 172.20.5.10/32 --dport 80 → KUBE-SVC-ABCDEF
  → KUBE-SVC-ABCDEF                        # 분배기: 확률 점프
      -m statistic --mode random --probability 0.333 → KUBE-SEP-AAA
      -m statistic --mode random --probability 0.500 → KUBE-SEP-BBB
      (잔여) → KUBE-SEP-CCC
  → KUBE-SEP-AAA                           # 엔드포인트: 진짜 일
      DNAT --to-destination 10.0.1.5:8080
```

확률의 산수: 3개 백엔드 = 1/3 → (남은 둘 중) 1/2 → 1 — 각 33.3%. **커넥션 단위**(첫 패킷에서만 평가, 이후는 conntrack) — HTTP keep-alive가 분배를 안 바꾸는 이유(모듈 05).

### conntrack — 보이지 않는 반쪽

```
첫 패킷: DNAT 적용 + conntrack에 기록 "10.0.9.9:3333 ↔ 172.20.5.10:80 (실제 10.0.1.5:8080)"
이후 패킷: 규칙 평가 없이 테이블 조회로 같은 변환
응답 패킷: 테이블 역참조로 src를 172.20.5.10:80으로 복원 ← 클라이언트는 Service와 통신한 줄로 압니다
```

- conntrack 테이블도 자원입니다: 한도(`nf_conntrack_max`) 초과 시 **새 연결 무작위 드롭** — "간헐 타임아웃"의 고전적 원인 (대량 커넥션 워크로드에서)
- UDP + conntrack의 함정: DNS처럼 상태 없는 UDP도 엔트리를 만들어, 백엔드 교체 시 낡은 엔트리가 잠시 블랙홀을 만들 수 있습니다

### 한계

- 규칙 매칭 O(n) (Service 수에 선형), 갱신은 **전체 테이블 교체**에 가까워 수만 규칙에서 초 단위
- 그래도 수백 Service 규모까지는 충분 — 성급한 최적화 금지

## 2. IPVS 모드

- 커널의 L4 로드밸런서(LVS). Service당 가상 서버 + 백엔드를 **해시 테이블**로 — O(1) 매칭
- 분배 알고리즘 선택: rr(라운드로빈)/wrr/lc(최소 연결)/sh(소스 해시)...
- 여전히 iptables 일부 사용(마스커레이드 등) + ipset으로 보조
- 선택 기준: Service/엔드포인트 수천~수만, 규칙 갱신 지연이 체감될 때

## 3. nftables 모드 (1.33 GA)

- iptables의 커널 후계자(nf_tables) 위에 재구현 — 증분 갱신, verdict map으로 매칭 효율화
- 장기적으로 iptables 모드를 대체할 방향. 신규 대규모 클러스터의 합리적 기본값 후보

## 4. eBPF — kube-proxy의 제거

Cilium의 kube-proxy replacement:

- **eBPF 프로그램**을 커널 훅(소켓 connect, tc/XDP)에 장착 — Service 변환을 **연결 시점**(socket-level)에 수행: 패킷마다가 아니라 connect() 한 번에 끝
- iptables 체인도 conntrack 의존도 줄이고 자체 BPF 맵으로 — 규칙 수와 무관한 O(1)
- 보너스: L7 인지(HTTP 메서드 단위 정책 — 모듈 15의 한계 돌파), 관측(Hubble), DSR 등
- 비용: 커널 버전 요구, 디버깅 도구 체계가 다름(iptables 지식이 안 통함) — cncf 파트 22에서 실전

## 5. 외부 트래픽의 특수 주제 (eks 파트 예고)

- `externalTrafficPolicy: Local`: NodePort/LB 트래픽을 **그 노드의 Pod로만** — 추가 홉/SNAT 제거로 **클라이언트 실제 IP 보존.** 대신 Pod 없는 노드는 헬스체크로 제외해야
- AWS LB Controller의 IP 타겟 모드: NLB/ALB가 노드포트를 거치지 않고 **Pod IP로 직접** (VPC CNI 덕분 — 모듈 27) — kube-proxy 홉 자체가 사라집니다

## 6. 소스코드에서 확인하기

- iptables 규칙 생성기: `pkg/proxy/iptables/proxier.go` `syncProxyRules` — 위 3계층 체인을 문자열로 찍어내는 거대 함수 (정독 가치 있음)
- nftables 모드: `pkg/proxy/nftables/`
- Cilium의 socket LB: https://github.com/cilium/cilium — `bpf/bpf_sock.c`

## 요약 카드

| 질문 | 답 |
|------|----|
| 분배의 구현체? | iptables statistic 모듈의 확률 점프 (커넥션 단위) |
| 응답 경로의 처리자? | conntrack (역변환) — 규칙은 가는 길만 |
| 간헐 타임아웃의 고전 원인? | conntrack 테이블 포화 |
| IPVS로 가는 시점? | Service/EP 수천 이상, 갱신 지연 체감 시 |
| eBPF 대체의 본질? | 패킷 단위 DNAT → 연결 시점 소켓 변환 (O(1)) |
| 클라이언트 IP 보존? | externalTrafficPolicy: Local 또는 LB의 IP 타겟 |
