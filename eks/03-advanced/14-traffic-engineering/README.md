# 14 — 트래픽 엔지니어링: ALB/NLB를 조종하는 법

> 13에서 앱 자체의 용량을 쟀습니다 — 그런데 유저는 앱을 직접 만나지 않습니다. **ALB라는 관문**의 타임아웃·알고리즘·드레이닝 설정이 체감 성능과 "배포 때마다 나는 502"를 좌우합니다. 이 모듈은 그 관문의 손잡이 전부를 돌려봅니다.

## 학습 목표

1. client→ALB→Pod 경로의 타임아웃 3종을 정렬합니다 (**idle timeout 정합의 원칙**)
2. 라우팅 알고리즘(round robin vs least outstanding requests)과 slow start의 자리를 압니다
3. 롤링 배포 중 5xx의 3대 원인을 해부하고 **무중단 배포를 실측으로 증명**합니다 (preStop·deregistration delay·readiness gate)
4. NLB의 세계(L4, cross-zone, client IP 보존)와 ALB의 차이를 압니다
5. LCU 과금 구조로 트래픽 설계의 비용 감각을 갖춥니다

## 선행: eks 08(ALB Controller), 13(측정 — 이 모듈의 도구), k8s 14(probe/preStop) · 환경: 공유 EKS
## ⚠️ 비용: ALB 시간당 + LCU — 실습 후 Ingress 삭제 필수 (LB 유출은 eks 최다 과금 사고)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-alb-tuning.md](./lab-01-alb-tuning.md) — ALB 경유 측정, 타임아웃 정합, 알고리즘 비교
3. [lab-02-zero-downtime.md](./lab-02-zero-downtime.md) — 배포 중 5xx 재현 → 0으로
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh` (★ ALB 소멸 확인)

소요: 이론 1.5h + 실습 2.5h
