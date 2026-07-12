# 01 — CI/CD의 정체: 자동화가 아니라 피드백 루프

> "젠킨스 돌리면 CI"라는 말은 "체온계가 있으면 건강하다"와 같습니다. CI는 도구가 아니라 **통합의 빈도**이고, CD는 **배포의 리스크를 잘게 쪼개는 전략**입니다. 이 모듈은 파이프라인을 만들기 전에, 그것이 무엇을 위한 장치인지 정의합니다 — 이후 27개 모듈의 모든 기술적 선택이 여기서 나온 질문에 답합니다.

## 학습 목표

1. CI / Continuous Delivery / Continuous Deployment를 **정확히** 구분합니다 (셋 다 "CD"라 불리는 혼란의 정리)
2. CI의 본질이 "빌드 자동화"가 아니라 **통합 주기 단축**임을 이해합니다 — merge hell의 수학
3. 파이프라인 설계 3원칙(빠른 피드백, 아티팩트 불변성, 신뢰의 게이트)을 세웁니다
4. DORA 4지표로 파이프라인의 성능을 정의합니다 — 개선의 좌표계
5. 배포 전략 스펙트럼(재생성 → 롤링 → 블루/그린 → 카나리)의 트레이드오프를 압니다

## 선행: git 기본기, k8s 파트 초급(배포 대상 이해) · 도구: git, Docker (실습은 로컬)
## 비용: 없음 (이 모듈은 클라우드 리소스를 만들지 않습니다)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-merge-hell.md](./lab-01-merge-hell.md) — 통합 주기의 비용을 git으로 실측
3. [lab-02-pipeline-design.md](./lab-02-pipeline-design.md) — 파이프라인 설계 워크시트 + DORA 측정
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 1.5h
