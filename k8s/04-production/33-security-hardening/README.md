# 33 — 보안 하드닝: 클러스터 차원의 방어 체계

> 실무 트랙 개막. 모듈 11/15/32에서 배운 개별 방어를 **클러스터 전체의 체계**로 묶습니다: CIS 벤치마크, 이미지 스캔/서명, 감사 체크리스트, 다층 방어 설계.

## 학습 목표

1. 다층 방어(4C: Cloud-Cluster-Container-Code)의 전체 지도를 그립니다
2. kube-bench로 CIS 벤치마크를 실행하고 결과를 해석합니다
3. trivy로 이미지/클러스터 취약점을 스캔하고 우선순위를 정합니다
4. 보안 감사 체크리스트(분기 루틴)를 갖춥니다
5. EKS 보안 분업(AWS 책임 vs 내 책임)을 명확히 합니다

## 선행: 모듈 11, 15, 23, 32 · 환경: 공유 EKS · 비용: 추가 없음

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-bench-scan.md](./lab-01-bench-scan.md) — kube-bench + trivy 실전
3. [lab-02-audit-checklist.md](./lab-02-audit-checklist.md) — 내 클러스터 셀프 감사
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
