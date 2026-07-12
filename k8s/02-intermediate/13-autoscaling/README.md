# 13 — 오토스케일링: HPA, VPA, 그리고 메트릭 파이프라인

> "손님 많으면 알바 더 부르기"의 자동화. HPA의 계산식, behavior 튜닝, VPA, 그리고 그 밑의 metrics-server 파이프라인까지.

## 학습 목표

1. 메트릭 파이프라인(kubelet→metrics-server→HPA)을 그릴 수 있습니다
2. HPA(autoscaling/v2)의 목표 추적 계산식을 이해하고 부하 실험으로 검증합니다
3. behavior(scaleUp/scaleDown 정책)로 출렁임(flapping)을 제어합니다
4. VPA의 용도와 HPA와의 충돌 조건을 압니다
5. requests가 없으면 HPA가 동작하지 않는 이유를 설명합니다

## 선행: 모듈 04, 12 · 환경: 공유 EKS (metrics-server는 1.36 EKS에 기본 포함)
## 비용: 부하 실험 중 Pod 증가분 (실습 후 정리)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-hpa.md](./lab-01-hpa.md) — CPU 기반 HPA + 부하 발생 + 스케일아웃/인 관찰
3. [lab-02-behavior-vpa.md](./lab-02-behavior-vpa.md) — behavior 튜닝, VPA 권고 모드
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 2h
