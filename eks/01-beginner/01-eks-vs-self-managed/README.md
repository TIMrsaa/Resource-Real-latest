# 01 — EKS vs 자체 운영: 무엇을 사고, 무엇이 남는가

> eks 파트 개막. k8s 파트에서 "전부"를 배웠으니, 이제 그중 **어디까지를 AWS에 위임하고 어디부터가 내 일인지**를 정확히 긋습니다 — 이 경계선이 eks 파트 전체의 지도입니다.

## 학습 목표

1. EKS가 관리하는 것(control plane)과 내 몫(데이터 평면+α)의 경계를 정확히 압니다
2. 요금 구조(시간당 클러스터 + 노드 + 네트워크)와 지원 정책(표준 14개월/연장 12개월)을 압니다
3. k8s 파트에서 배운 컴포넌트들이 EKS에서 "어디에 있는지" 매핑합니다
4. 공유 책임 모델을 보안/운영 관점에서 그립니다
5. 실습 클러스터의 구조를 AWS API로 해부합니다

## 선행: k8s 파트 01~10 (특히 02 아키텍처) · 환경: 공유 EKS (k8s 파트에서 만든 k8s-study)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-anatomy.md](./lab-01-anatomy.md) — 내 클러스터 해부 (AWS API로)
3. [lab-02-cost-worksheet.md](./lab-02-cost-worksheet.md) — 비용 해부와 절감 지도
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) (cleanup 불필요 — 읽기만)

소요: 이론 1h + 실습 1.5h
