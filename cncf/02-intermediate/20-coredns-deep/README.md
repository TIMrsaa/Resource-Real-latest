# 20 — CoreDNS 심층: 클러스터의 이름을 답하는 자

> 04의 네트워킹 지도에서 [DNS·디스커버리] 층의 주인. 모든 K8s 통신이 이름으로 시작하고, 그 이름을 IP로 바꾸는 것이 CoreDNS입니다 — 그래서 **CoreDNS가 느리면 클러스터 전체가 느립니다.** 이 모듈은 세 축을 팝니다: 플러그인 체인 아키텍처(Corefile이 곧 프로그램), K8s 이름 해석의 실제(ndots:5라는 악명 높은 기본값과 검색 도메인 폭발), 그리고 성능·장애의 물리학(캐시, NodeLocal DNSCache, conntrack 경쟁 조건).

## 학습 목표

1. 플러그인 체인 아키텍처와 Corefile의 실행 모델을 압니다 (순서가 곧 로직)
2. `ndots:5`와 search 도메인이 만드는 쿼리 증폭을 실측하고 대응합니다
3. kubernetes 플러그인의 레코드 종류(A/SRV/PTR, headless·ExternalName)를 압니다
4. 캐시·자동경로(autopath)·NodeLocal DNSCache로 지연과 부하를 줄입니다
5. 대표 장애(외부 도메인 해석 실패, 간헐 5초 지연, CoreDNS OOM)를 진단합니다

## 선행: 04(네트워킹 지도), k8s(Service·DNS 기초), eks 18(패킷 경로) · 도구: kind, kubectl, dig
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-corefile-and-ndots.md](./lab-01-corefile-and-ndots.md) — 플러그인 체인, ndots 증폭 실측
3. [lab-02-performance-and-failures.md](./lab-02-performance-and-failures.md) — 캐시·NodeLocal, 장애 재현
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
