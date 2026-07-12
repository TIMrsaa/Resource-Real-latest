# 10 — 지도: 플랫폼·자동화·나머지 — 그리고 지도 전체의 종합

> 지도 트랙의 마지막. 앞의 여덟 칸에 안 들어가는 주민들 — 오토스케일링(KEDA·Karpenter), 서버리스·Wasm(Knative·wasmCloud), 비용(OpenCost), 카오스(Chaos Mesh·Litmus), 레지스트리(Harbor), 그리고 **플랫폼 엔지니어링**이라는 이 시대의 조립 문법 — 을 다룹니다. 그리고 후반부는 이 트랙의 진짜 목적입니다: 아홉 개 지도를 하나의 종합 지도로 접고, 우리 스택의 좌표와 공백을 그리는 **개인 지도 만들기**.

## 학습 목표

1. 나머지 주민들을 다섯 갈래(오토스케일·서버리스/Wasm·비용·카오스·레지스트리)로 정리합니다
2. KEDA와 Karpenter의 층 구분(워크로드 스케일 vs 노드 프로비저닝)을 정확히 압니다
3. 플랫폼 엔지니어링을 "지도의 조립 문법"으로 이해합니다 — 왜 IDP가 이 시대의 답인지
4. 아홉 지도를 종합해 **하나의 판단 순서도**를 만듭니다 (증상 → 카테고리 → 후보 → 소견서)
5. kind에서 KEDA로 이벤트 기반 스케일링을 시식하고, OpenCost로 비용을 관측합니다

## 선행: 01~09 (전 지도), eks 17(Karpenter), cicd 15(KEDA 언급) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md) — 나머지 주민 + 종합 지도
2. [lab-01-category-census.md](./lab-01-category-census.md) — 전수 마감·미분류 잔여 확인
3. [lab-02-keda-and-synthesis.md](./lab-02-keda-and-synthesis.md) — KEDA 시식 + 개인 종합 지도 작성
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2.5h
