# 11 — 관리형 애드온: 클러스터 부품의 버전 관리

> vpc-cni(07), EBS CSI(10), Pod Identity 에이전트(09)... 계속 만나온 "관리형 애드온"의 체계 자체를 다룹니다 — 버전 호환성, 설정 주입(configuration-values), 그리고 "내 수정이 사라지는" 충돌 해결의 원리.

## 학습 목표

1. 애드온 체계(무엇이 애드온인가, 자가 관리 대비 무엇이 다른가)를 압니다
2. 버전 선택(default vs latest)과 K8s 버전 호환성을 조회합니다
3. configuration-values(+스키마)로 애드온을 선언적으로 설정합니다
4. 충돌 해결 모드(OVERWRITE/PRESERVE)와 "kubectl 수정이 원복되는" 원리를 압니다
5. 클러스터 업그레이드와 애드온의 순서(21의 부품)를 정리합니다

## 선행: 모듈 07/09/10 (애드온 사용 경험), k8s 35 · 환경: 공유 EKS

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-inventory-config.md](./lab-01-inventory-config.md) — 인벤토리, 스키마, 선언적 설정
3. [lab-02-versions-conflicts.md](./lab-02-versions-conflicts.md) — 버전 업과 충돌 해결 실험
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) (cleanup: 변경 원복 안내 포함)

소요: 이론 1h + 실습 1.5h
