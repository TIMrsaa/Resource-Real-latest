# 학습 가이드 — "읽을 줄 알면" 무섭지 않습니다

## iptables 공포 해독제

`iptables-save | wc -l`이 수천 줄이어도, kube-proxy가 만드는 구조는 단 3계층의 반복입니다:

```
KUBE-SERVICES        "모든 Service의 목차" — ClusterIP:port 매칭
  └ KUBE-SVC-XXXX    "한 Service의 분배기" — 확률로 백엔드 선택
      └ KUBE-SEP-YYY "한 백엔드(엔드포인트)" — 실제 DNAT 실행
```

lab-01에서 우리 Service 하나를 이 3계층으로 끝까지 추적합니다. 한 번 해보면 수천 줄이 "같은 패턴의 복제"로 보이기 시작합니다.

## 이 모듈의 비밀 두 가지

1. **분배는 확률입니다**: 백엔드 3개면 "33% 확률 → 안 걸리면 50% → 안 걸리면 나머지" — iptables의 statistic 모듈. 모듈 05에서 "라운드로빈이 아니라 무작위"라고 한 말의 구현체.
2. **응답 규칙은 없습니다**: DNAT은 가는 길만 바꿉니다. 오는 길은 **conntrack**(연결 추적 테이블)이 기억해뒀다 역변환 — NetworkPolicy가 stateful(모듈 15)인 것도 같은 테이블 덕입니다.

## 세대 교체의 줄거리

```
iptables (기본)   체인 선형 탐색 — Service 수천 개에서 규칙 갱신/매칭 비용 급증
IPVS              커널 L4 LB — 해시 테이블, 대규모에 강함, 알고리즘 선택(rr/lc...)
nftables (1.33+)  iptables의 후계 커널 기능 — 갱신 성능 개선
eBPF (Cilium)     kube-proxy 자체를 제거 — 소켓/XDP 레벨에서 처리, conntrack도 자체
```

EKS 기본은 여전히 iptables — 대부분 규모에서 충분합니다. "수천 Service + 수만 엔드포인트"가 보이면 위 사다리를 검토하는 것 (cncf 파트 22에서 Cilium 실전).
