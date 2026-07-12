# 18 — 네트워크 심층: 패킷의 여행을 끝까지 따라가기

> "Pod A에서 B로 안 가요"의 최종 병기는 도구가 아니라 **경로의 지도**입니다 — 패킷이 veth를 나와 노드 라우팅을 타고, ENI를 지나, SG·NACL·NetworkPolicy라는 세 검문소를 통과하는 전 구간. 이 모듈은 그 지도를 실측으로 그리고, VPC Flow Logs로 "어디서 죽었는지"를 증거로 찾는 법을 만듭니다.

## 학습 목표

1. VPC CNI 세계의 패킷 경로 4종(같은 노드, 다른 노드, 외부로, 밖에서 유입)을 그림으로 그립니다 — **오버레이 없음**의 의미
2. 노드에 들어가 라우팅 테이블·veth에서 그 경로를 실측 확인합니다
3. 검문소 3층(SG/NACL/NetworkPolicy)의 관할·상태성·집행자를 구분합니다
4. VPC Flow Logs를 켜고 Logs Insights로 ACCEPT/REJECT를 심문합니다 — 그리고 **Flow Logs가 못 보는 것**(NP 드롭)을 압니다
5. "A→B 불통" 진단 계단(DNS→NP→SG→NACL→라우팅→FlowLogs)을 루틴으로 갖춥니다

## 선행: eks 07(VPC CNI), 14(ALB 경로), k8s 15(NetworkPolicy), 16(CoreDNS), 12(Logs Insights) · 환경: 공유 EKS
## ⚠️ 비용: Flow Logs 수집(GB) — 짧게 켜고 cleanup에서 로그 그룹까지 삭제

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-packet-path.md](./lab-01-packet-path.md) — veth·라우팅·ENI 실측 추적
3. [lab-02-flowlogs-firewalls.md](./lab-02-flowlogs-firewalls.md) — Flow Logs 심문, 검문소 실험
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
