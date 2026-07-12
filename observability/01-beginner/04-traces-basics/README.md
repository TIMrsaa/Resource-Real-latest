# 04 — 트레이스의 원리: 요청의 여정을 잇는 실

> 01에서 확인했듯 트레이스는 유일하게 **앱이 만들어야** 태어나는 신호입니다. 이 모듈은 그 신호의 구조를 팝니다 — trace와 span의 모델(요청 하나 = 트리 하나), **컨텍스트 전파**(W3C traceparent 헤더가 서비스 경계를 넘어 실을 잇는 방법), 그리고 "왜 이 실이 없으면 분산 조사가 팀 간 떠넘기기가 되는가". 파이프라인·백엔드 없이 개념과 최소 실습(헤더를 손으로 전파해 보기)에 집중합니다 — 자동 계측·Collector 배포는 11에서, 백엔드 선택(Jaeger/Tempo/X-Ray)은 12·17에서. cncf 12(OTel 내부)·13(Jaeger)의 실무 입문판이자, 12(신호 상관)의 전제입니다.

## 학습 목표

1. trace/span 모델(트리 구조, span의 구성 요소)을 그릴 수 있습니다
2. W3C traceparent 헤더의 구조와 전파 원리를 설명할 수 있습니다
3. "전파가 끊기는 지점"(비동기 경계·전파 누락)과 결과를 압니다
4. 샘플링이 왜 필수이고 head/tail의 차이가 무엇인지 개념을 잡습니다 (cncf 12 연결)
5. 분산 조사에서 트레이스가 답하는 질문("어디가 느린가")의 위치를 압니다

## 선행: 01(신호 분담 — 필수), 02·03, cncf 12(병행 권장) · 도구: kind, kubectl
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-trace-model-by-hand.md](./lab-01-trace-model-by-hand.md) — traceparent를 손으로 만들고 전파해 모델 체득
3. [lab-02-broken-propagation.md](./lab-02-broken-propagation.md) — 전파가 끊긴 시스템의 조사 불능 체감
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 1.5h
