# 학습 가이드 — DNS는 조용히 모든 것을 느리게 만듭니다

## 왜 DNS가 클러스터의 급소인가

애플리케이션이 `http://payment/api`를 호출합니다. 그 전에 무슨 일이 일어나는가요?

```
1. 이름 해석: "payment"가 무엇인가요? → CoreDNS에 질의
2. 그런데 "payment"는 완전한 이름이 아닙니다 → search 도메인을 붙여 여러 번 시도
   payment.default.svc.cluster.local  → 성공하면 끝
   (실패하면) payment.svc.cluster.local
   (실패하면) payment.cluster.local
   (실패하면) payment (외부 DNS로)
3. 각 시도마다 A와 AAAA 두 질의 (IPv6 스택이 켜져 있으면)
```

즉 **HTTP 요청 하나가 DNS 질의 2~8개를 만듭니다**. 초당 1만 요청이면 초당 수만 DNS 질의입니다. 그리고 이 증폭의 원인인 `ndots:5`는 K8s의 기본값입니다.

DNS가 느려지면 모든 서비스 호출이 느려지고, 원인은 애플리케이션 메트릭 어디에도 안 보입니다(요청 지연에 녹아 있을 뿐). 그래서 "왜인지 모르게 p99가 높은" 클러스터의 첫 용의자가 DNS입니다.

## Corefile은 설정 파일이 아니라 프로그램입니다

CoreDNS의 설계는 우아합니다 — 플러그인들이 체인으로 연결되고, 질의가 그 체인을 타고 흐릅니다:

```
.:53 {
    errors
    health
    kubernetes cluster.local { ... }   ← 이 플러그인이 답할 수 있으면 여기서 응답
    forward . /etc/resolv.conf         ← 못 하면 상위 DNS로
    cache 30                            ← 응답을 캐시
    loop
    reload
}
```

**순서가 의미입니다.** `cache`를 `kubernetes` 앞에 두면 클러스터 레코드도 캐시되고, `forward` 뒤에 두면 외부 응답만 캐시됩니다. 이 체인 사고를 이해하면 Corefile을 읽는 것이 프로그램을 읽는 것과 같아집니다 — 06의 OTel Collector 파이프라인(receivers→processors→exporters)과 같은 계열의 설계입니다.

## 세 가지 유명한 장애

이 모듈이 재현하고 진단하는 것들:

```
① 간헐적 5초 지연 — conntrack의 DNAT 경쟁 조건(커널). 원인이 CoreDNS가 아닌데 CoreDNS를 의심합니다
② 외부 도메인 해석 실패 — forward 대상(노드의 resolv.conf)이 잘못됐거나 loop 감지
③ CoreDNS OOM/지연 — 쿼리 증폭(ndots) + 캐시 미스 + replicas 부족
```

셋 다 "DNS 문제"로 보이지만 층이 다릅니다(커널 / 설정 / 용량). 층을 나누는 것이 이 모듈의 실무 가치입니다.
