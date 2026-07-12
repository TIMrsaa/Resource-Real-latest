# 07 — Fluentd 애그리게이터: 수집과 집계의 2층 구조

> 06에서 노드 수집기(Fluent Bit)를 세웠습니다. 그런데 규모가 커지면 질문이 생깁니다 — 노드 수백 대가 **각자** 목적지(OpenSearch·S3·외부 SaaS)에 직접 연결해야 하나요? 목적지 인증서를 노드 전부에? 복잡한 가공(민감정보 마스킹·레코드 변형·다중 라우팅)을 노드마다? 이 질문의 답이 **2층 구조** — 가벼운 수집기(Fluent Bit, 노드)가 무거운 애그리게이터(Fluentd, 중앙 Deployment)로 forward하고, 애그리게이터가 가공·라우팅·배달을 맡는 패턴입니다. 이 모듈은 Fluentd의 설정 모델(match·copy·라벨), forward 프로토콜(신뢰성 옵션), 2층의 장단(운영점 추가 vs 노드 단순화), 그리고 "언제 2층이 필요하고 언제 과한가"의 판단을 다룹니다. cncf 14(Fluentd 내부)의 실전 배치판입니다.

## 학습 목표

1. 2층 구조(수집기→애그리게이터)가 푸는 문제와 만드는 문제를 압니다
2. Fluentd 설정 모델(source·match·filter·label·copy)을 읽고 씁니다
3. forward 프로토콜의 신뢰성(ack·재시도·로드밸런싱)을 설정합니다
4. 애그리게이터의 대표 역할(마스킹·다중 출력·재라우팅)을 구현합니다
5. Fluent Bit 단독 vs 2층의 판단 기준을 세웁니다 (규모·가공 복잡도·목적지 수)

## 선행: 06(Fluent Bit — 필수), cncf 14(Fluentd 버퍼 내부) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-two-tier-pipeline.md](./lab-01-two-tier-pipeline.md) — Bit→Fluentd forward 2층 구축
3. [lab-02-aggregator-roles.md](./lab-02-aggregator-roles.md) — 마스킹·copy 다중 출력·판단
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
