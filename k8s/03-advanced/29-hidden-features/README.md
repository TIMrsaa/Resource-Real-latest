# 29 — 숨겨진 기능 대전 (Hidden Features)

> 문서 구석과 feature gate 뒤에 숨어 있는, 아는 사람만 쓰는 기능들의 총집합. v1.36 기준으로 "최근 GA가 된 신무기"와 "오래됐지만 묻힌 보석"을 한 모듈에 모았습니다.

## 학습 목표

1. feature gate 체계와 기능 성숙 단계(Alpha→Beta→GA)를 이해하고, KEP로 기능의 역사를 추적합니다
2. 신무기 사용: in-place Pod resize, sidecar(이미 배움), PodDisruptionConditions, Job 정밀 제어
3. 묻힌 보석 사용: ephemeral container 심화, Downward API, projected volume, topology aware routing 등 15+ 기능
4. "이 기능이 우리 클러스터에서 되나요?"를 스스로 판별하는 루틴을 갖춥니다

## 선행: 모듈 21~28 (대부분의 기능이 그 토대 위에 있습니다) · 환경: 공유 EKS(1.36)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md) — 기능 카탈로그 (이 모듈의 본체)
2. [lab-01-new-weapons.md](./lab-01-new-weapons.md) — in-place resize 등 신무기 실습
3. [lab-02-hidden-gems.md](./lab-02-hidden-gems.md) — 묻힌 보석 연쇄 실습
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2h
