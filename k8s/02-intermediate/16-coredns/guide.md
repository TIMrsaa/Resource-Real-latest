# 학습 가이드 — DNS는 "조용한 공범"입니다

## 왜 한 모듈을 통째로 쓰나

DNS는 잘 돌 때는 존재감이 없지만, K8s 장애 사후분석에 단골로 등장합니다:

- 모든 서비스 간 호출의 **첫 단계**가 DNS입니다 — DNS가 느리면 전부 느립니다
- 기본 설정(ndots:5)이 **외부 도메인 호출마다 불필요한 질의 4번**을 만듭니다
- CoreDNS는 기본 2 replicas — 대규모 클러스터에서 과부하 지점이 됩니다

"앱은 빠른데 가끔 첫 요청만 2초 걸려요", "외부 API 호출이 5초씩 타임아웃" — 범인이 DNS인 경우가 많고, 이 모듈이 그 수사법입니다.

## 미리 잡는 핵심: 이름 해석은 "검색 목록 순회"다

Pod에서 `api`라는 짧은 이름이 풀리는 이유는 마법이 아니라 resolv.conf의 **search 목록** 덕분입니다:

```
search default.svc.cluster.local svc.cluster.local cluster.local
ndots: 5
```

`api` → 점이 5개 미만 → "불완전한 이름"으로 간주 → `api.default.svc.cluster.local`부터 순서대로 붙여가며 질의. **편리함의 비용**: `www.google.com`(점 2개)도 불완전 취급되어 `www.google.com.default.svc.cluster.local`... 4번의 실패 질의 후에야 진짜 질의를 합니다. 이것이 ndots 문제의 전부 — lab-02에서 패킷 수준으로 확인합니다.

## 연결

- 모듈 05: Service DNS 레코드의 출처
- 모듈 15: egress 정책의 DNS 조각이 왜 필수였는지 재확인
- 대규모 튜닝(NodeLocal DNSCache)은 모듈 37에서
