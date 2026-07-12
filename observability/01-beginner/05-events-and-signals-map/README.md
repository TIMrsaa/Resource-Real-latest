# 05 — 이벤트와 신호 지도: 네 신호를 하나의 지도로

> beginner 트랙의 마무리. 남은 신호인 **K8s Events**(1시간 휘발의 보물)와 **audit 로그**(누가 무엇을 했나)를 다루고, 01~04에서 배운 네 신호를 하나의 **신호 지도**로 종합합니다 — 각 신호의 원산지·수명·비용·답하는 질문을 한 장에. 그리고 실무 질문 카탈로그("Pod가 왜 죽었지?", "누가 이 설정을 바꿨지?", "왜 이 시간만 느렸지?")를 지도에 대응시키는 훈련으로, "무슨 일이 생기면 어느 신호부터 여는지"의 반사신경을 만듭니다. 졸업 과제는 SIGNALS-MAP.md — 자기 손으로 그리는 신호 지도입니다. 이 지도를 들고 intermediate(06~12)에서 파이프라인을 짓습니다.

## 학습 목표

1. K8s Events의 구조(Reason·Type·involvedObject)와 휘발성 대응(수집·보존)을 압니다
2. audit 로그의 역할(누가·무엇을·언제)과 레벨(None~RequestResponse)을 압니다
3. 네 신호의 원산지·수명·비용·질문을 한 장의 지도로 그릴 수 있습니다
4. 실무 질문 카탈로그를 신호 지도에 대응시킬 수 있습니다 (조사 반사신경)
5. 졸업 과제: 자기 클러스터의 SIGNALS-MAP.md 작성

## 선행: 01~04 전부 (이 모듈은 종합) · 도구: kind, kubectl
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-events-and-audit.md](./lab-01-events-and-audit.md) — Events 해부·수집, audit 로그 활성화
3. [lab-02-signals-map-capstone.md](./lab-02-signals-map-capstone.md) — 질문 카탈로그 훈련 + SIGNALS-MAP.md 졸업 과제
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h (졸업 과제 포함)
