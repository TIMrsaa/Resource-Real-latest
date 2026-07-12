# 16 — CoreDNS: 클러스터 DNS의 모든 것

> 지금까지 당연하게 써온 `http://api.shop` 이름 해석의 내부. Corefile, ndots 문제, DNS가 성능 병목이 되는 메커니즘까지.

## 학습 목표

1. Pod의 /etc/resolv.conf가 어떻게 만들어지는지 압니다
2. Service/Pod/Headless DNS 레코드 체계를 압니다
3. **ndots:5 문제** — K8s DNS 성능 이슈의 8할 — 를 재현하고 해결합니다
4. Corefile 구조를 읽고 수정합니다 (로깅, 커스텀 도메인 포워딩)
5. DNS 장애 디버깅 루틴을 익힙니다

## 선행: 모듈 05, 09 · 환경: 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-dns-records.md](./lab-01-dns-records.md) — 레코드 체계와 resolv.conf 해부
3. [lab-02-ndots-corefile.md](./lab-02-ndots-corefile.md) — ndots 재현, Corefile 수정
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 1.5h
