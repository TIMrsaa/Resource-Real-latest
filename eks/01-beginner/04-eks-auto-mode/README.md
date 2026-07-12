# 04 — EKS Auto Mode: 노드 운영의 소멸

> 모듈 01의 경계선이 한 번 더 이동합니다 — Auto Mode는 노드/오토스케일링/핵심 애드온/LB·스토리지 컨트롤러까지 AWS가 가져갑니다. "무엇이 더 넘어갔고, 그 대가가 무엇인지"를 직접 켜보며 측정합니다.

## 학습 목표

1. Auto Mode가 추가로 가져가는 것(노드 수명주기, 내장 Karpenter, 내장 컨트롤러)을 압니다
2. 표준 모드와의 경계선 차이를 표로 그립니다 (모듈 01의 업데이트)
3. 기존 클러스터에 Auto Mode를 켜고 NodePool로 워크로드를 띄웁니다
4. 제약(노드 접근 불가, 21일 수명, 추가 요금)과 적합/부적합 시나리오를 판별합니다

## 선행: 모듈 01~03 · 환경: 공유 EKS (Auto Mode 병행 활성화 — 비용 주의)

> ⚠️ Auto Mode는 빠르게 진화 중 — 실습 전 공식 문서에서 현재 기능/요금을 재확인하세요.

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-enable-automode.md](./lab-01-enable-automode.md) — 켜고, 띄우고, 노드 출생 관찰
3. [lab-02-builtin-capabilities.md](./lab-02-builtin-capabilities.md) — 내장 기능과 제약 체험
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1h + 실습 1.5h
