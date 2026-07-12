# 10 — 알림과 Alertmanager: 새벽 3시에 울릴 자격

> 대시보드(09)는 보러 가야 하지만, 알림은 찾아옵니다 — 그래서 더 엄격해야 합니다. 잘못된 알림 체계는 두 방향으로 실패합니다: 울려야 할 때 침묵(08의 사고)하거나, **너무 자주 울려 무시당하거나**(알림 피로 — 더 흔하고 더 위험). 이 모듈은 알림 규칙 작성의 규율(증상 기반·지속 시간·심각도), PromQL 알림의 실전 패턴(for·keep_firing_for·absent), 그리고 Alertmanager의 본체 — **라우팅 트리·그룹핑·억제(inhibition)·사일런스** — 로 "울릴 자격이 있는 알림만, 맞는 사람에게, 한 번만" 도달하게 만드는 법을 다룹니다. 21(SLO 번레이트)이 이 위에 얹히는 고급 알림 전략이고, 23(온콜)이 이 알림을 받는 사람의 이야기입니다.

## 학습 목표

1. 좋은 알림의 조건(증상 기반·행동 가능·긴급성 구분)을 세웁니다
2. 알림 규칙의 실전 문법(expr·for·labels·annotations·runbook 링크)을 씁니다
3. Alertmanager 라우팅 트리(매칭·그룹핑·반복)를 설계합니다
4. 억제(inhibition)와 사일런스로 알림 폭풍·중복을 통제합니다
5. 알림 피로의 원인과 대책(리뷰 루프·삭제의 용기)을 압니다

## 선행: 08(recording rules — 필수), 09(착지 대시보드) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-alert-rules.md](./lab-01-alert-rules.md) — 알림 규칙 작성·발화 관찰 (좋은 알림의 해부)
3. [lab-02-alertmanager-routing.md](./lab-02-alertmanager-routing.md) — 라우팅·그룹핑·억제·사일런스
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2h
