# 12 — OpenTelemetry 심층: 계측 표준, 컨텍스트 전파, Collector 파이프라인

> CNCF에서 Kubernetes 다음으로 큰 프로젝트. 06의 격자에서 [전 신호 × 수집·전송] 칸을 통째로 맡았고, 야심은 명확합니다 — **계측을 벤더로부터 해방합니다**. 이 모듈은 세 축을 팝니다: **컨텍스트 전파**(트레이스가 서비스 경계를 넘는 메커니즘 — W3C traceparent), **시맨틱 컨벤션**(같은 것을 같은 이름으로 부르기 — 표준의 진짜 가치), **Collector**(receivers→processors→exporters의 게이트웨이, 배포 토폴로지, 샘플링). 그리고 OTel이 하지 않는 것의 경계를 다시 못 박습니다.

## 학습 목표

1. 데이터 모델(트레이스: span/context, 메트릭, 로그)과 신호 간 상관(trace_id로 잇기)을 이해합니다
2. 컨텍스트 전파의 메커니즘 — W3C traceparent 헤더, propagator, 전파 끊김의 원인 — 을 압니다
3. 시맨틱 컨벤션이 왜 표준의 핵심 가치인지 설명합니다 (대시보드 이식성)
4. Collector의 세 파이프라인 단계와 배포 토폴로지(agent/gateway)를 설계합니다
5. 샘플링 전략(head vs tail)의 트레이드오프를 알고 tail 샘플링을 실습합니다

## 선행: 06(관측 지도), 11(Prometheus), eks 12·13 · 도구: kind, kubectl, helm, python3
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-context-propagation.md](./lab-01-context-propagation.md) — 두 서비스로 트레이스 잇기, 전파 끊김 재현
3. [lab-02-collector-pipeline.md](./lab-02-collector-pipeline.md) — Collector 파이프라인·샘플링·백엔드 교체
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2.5h
