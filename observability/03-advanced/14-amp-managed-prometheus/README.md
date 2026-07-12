# 14 — AMP(Amazon Managed Prometheus): 저장만 넘기고 체계는 지킵니다

> 08에서 "단일 Prometheus는 장기·대규모 저장용이 아닙니다 — remote_write로 위임하라"고 했습니다. AMP가 그 위임의 관리형 답입니다: PromQL·알림 규칙·remote_write 프로토콜을 그대로 쓰면서, TSDB의 저장·확장·가용성을 AWS가 맡습니다. 이 모듈의 핵심 통찰은 **"수집 체계(08)는 그대로"** — ServiceMonitor·relabeling·recording rules는 클러스터에 남고, 저장만 워크스페이스로 간다는 것. 에이전트 모드(수집 전용 Prometheus), SigV4 인증(IRSA — eks 파트의 그것), AMP의 규칙·Alertmanager(관리형), 그리고 "자체 Prometheus vs AMP vs Thanos/Mimir(24)"의 판단을 다룹니다.

## 학습 목표

1. remote_write 아키텍처(로컬 수집 → 원격 저장)와 에이전트 모드를 이해합니다
2. AMP 워크스페이스를 만들고 IRSA(SigV4)로 remote_write를 연결합니다
3. 08의 체계(SM·relabeling·rules)가 AMP에서 어떻게 유지·이관되는지 확인합니다
4. AMP의 요금 모델(샘플 ingest·저장·쿼리)과 카디널리티의 관계를 압니다
5. 자체 Prometheus vs AMP vs Thanos/Mimir의 판단 축을 세웁니다

## 선행: 08(수집 체계 — 필수), 13(관리형 요금 감각), eks 파트(IRSA) · 도구: AWS 계정, EKS, helm, awscurl(또는 SigV4 도구)
## 비용: ⚠️ 발생 — AMP 샘플 ingest·저장·쿼리, EKS. cleanup.sh 필수

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-remote-write-irsa.md](./lab-01-remote-write-irsa.md) — 워크스페이스·IRSA·remote_write 연결
3. [lab-02-rules-and-judgment.md](./lab-02-rules-and-judgment.md) — AMP 규칙·쿼리, 판단 정리
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2h
