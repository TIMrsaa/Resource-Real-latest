# 14 — Fluentd / Fluent Bit 심층: 로그 파이프라인의 물리학

> 관측 심층의 마지막 신호. 06의 격자에서 [로그 × 전송·가공] 칸의 주인이고, eks 12에서 CloudWatch로 흘려보내던 그 파이프라인의 오픈소스 원본입니다. 로그가 메트릭·트레이스와 결정적으로 다른 점은 **볼륨이 비싸고 손실이 조용하다**는 것 — 이 모듈은 그 물리학을 팝니다: 로그가 파일에서 백엔드까지 가는 경로(tail → parse → filter → buffer → output), 버퍼링과 백프레셔(로그를 잃는 진짜 이유), Fluentd와 Fluent Bit의 갈림, 그리고 12·13과 잇는 마지막 조각(trace_id 구조화 필드).

## 학습 목표

1. 컨테이너 로그의 실제 경로(stdout → CRI 로그 파일 → 에이전트 → 백엔드)를 압니다
2. 파이프라인 5단계(input/parser/filter/buffer/output)와 각 단계의 실패 모드를 압니다
3. 버퍼링·백프레셔·재시도 — 로그가 유실되는 세 가지 방식 — 을 실험으로 확인합니다
4. Fluentd와 Fluent Bit의 설계 차이(Ruby vs C, 플러그인 vs 성능)와 조합 패턴을 압니다
5. 구조화 로깅과 trace_id 필드로 06·12·13의 조사 동선을 완성합니다

## 선급: 06(격자), 11·12·13(관측 심층), eks 12(로그 파이프라인) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-pipeline-and-loss.md](./lab-01-pipeline-and-loss.md) — 로그 경로 추적, 버퍼·유실 재현
3. [lab-02-structured-and-correlated.md](./lab-02-structured-and-correlated.md) — 구조화 로깅 + trace_id 상관
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
