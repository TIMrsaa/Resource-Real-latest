# Lab 01 — runbook 작성과 동선 연결

> 21의 번레이트 알림에 대응하는 runbook을 실제로 작성하고, 알림→runbook→대시보드→완화의 사슬을 연결합니다. lab-02(게임데이)에서 이 runbook이 시험대에 오릅니다.

## 0. 준비 — 21의 스택 재구축 (SLO·번레이트 알림 포함)

```bash
kind create cluster --name incident
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null; helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace --set prometheus.prometheusSpec.retention=24h

# payment 앱 v1 (안정 버전) + SM + SLI rules + 번레이트 알림 — 21의 세트
kubectl create namespace shop
# (21 lab-01·02의 매니페스트 적용 — payment/Service/SM/PrometheusRule 세트)
# 지면 관계상 동일 세트 생략 표기 — 21의 yaml을 그대로 적용하세요
```

## 1. runbook 작성 — 알림 하나에 문서 하나

```bash
mkdir -p runbooks
cat > runbooks/payment-budget-fast-burn.md <<'EOF'
# PaymentBudgetFastBurn — 결제 SLO 버짓 급속 소진

## 의미 (한 줄)
결제 서비스의 에러율이 SLO(98%)를 지킬 수 없는 속도(번레이트 14.4×)로
버짓을 태우는 중 — 이 속도면 기간 버짓이 ~2일 내 소진. 사용자 영향 진행 중.

## 즉시 확인 (3분)
1. L1 대시보드: http://grafana/d/svc-overview — payment 행의 에러율·추세
2. 배포 확인: 대시보드의 배포 마커 — ★ 최근 60분 내 배포가 있는가요?
   (또는) kubectl -n shop rollout history deploy/payment
3. 범위 확인: 에러가 특정 Pod인가 전체인가
   sum by (pod) (rate(http_requests_total{namespace="shop",code=~"5.."}[5m]))

## 완화 후보 (조건 → 조치)
| 조건 | 조치 |
|------|------|
| 최근 60분 내 배포 있음 | ★ 즉시 롤백: kubectl -n shop rollout undo deploy/payment — 원인 규명은 롤백 후 |
| 특정 Pod만 에러 | 해당 Pod 삭제(재생성): kubectl -n shop delete pod <pod> |
| 전체 + 배포 없음 | 의존성 확인(DB·외부 PG — 트레이스에서 병목 span) → 페일오버/기능 플래그 검토 |
| 트래픽 폭증 동반 | 스케일 아웃: kubectl -n shop scale deploy/payment --replicas=N |

## 에스컬레이션
- 15분 내 완화 실마리 없음 → 팀 리드 호출
- 데이터 정합 의심(중복 결제 등) → SEV1 상향, DBA + 경영 통지

## 함정 (하지 말 것)
- 전 Pod 동시 재시작 금지 — 콜드 캐시 스탬피드로 악화된 전례 (2026-03 사고)
- Prometheus/모니터링 재시작 금지 — 조사 능력을 잃습니다 (03 사고 참고)
EOF
```

**구조 점검** — theory 4절의 5요소가 다 있는가: 의미(왜 깨웠나), 즉시(첫 3개 — 복붙 가능), 완화 후보(조건→조치 표 — "배포 있으면 롤백"이 1순위인 것에 주목), 에스컬레이션(시간 기준), 함정(과거의 유산). **"원인 규명은 롤백 후"** — 완화 우선의 원칙이 문서에 박혀 있습니다.

## 2. 사슬 연결 — 알림이 runbook을 물고 오게

```bash
# 21의 알림 규칙에서 annotation 확인/보강 (10의 규율)
kubectl -n shop get prometheusrule payment-burnrate -o yaml | grep -A3 annotations
# annotations에:
#   runbook: "https://github.com/<org>/runbooks/blob/main/payment-budget-fast-burn.md"
#   dashboard: "http://grafana/d/svc-overview"
# → 실전: runbooks/를 Git 저장소로, 알림 링크는 그 URL로 (as code)
```

```
사슬의 검증 (조용한 끊김 방지 — 09·12의 규율):
  □ 알림 페이로드에 runbook 링크가 실려 오는가 (10 lab-02의 웹훅으로 확인)
  □ 링크가 실제 문서에 도달하는가 (경로 오타·이동)
  □ runbook의 명령이 현재 환경에서 유효한가 (네임스페이스·리소스명)
  □ 대시보드 uid가 살아 있는가 (09)
→ lab-02의 게임데이가 이 전부를 실전 형식으로 검증합니다
```

## 3. 완화 도구의 사전 점검 — 롤백은 준비된 자의 것

```bash
# 롤백이 runbook의 1순위 완화라면 — 롤백이 실제로 되는가를 평시에 확인
kubectl -n shop rollout history deploy/payment
# revision이 쌓여 있는가요? (revisionHistoryLimit 확인)
kubectl -n shop set env deploy/payment DUMMY=v2   # 가짜 배포로 리비전 생성
kubectl -n shop rollout status deploy/payment
kubectl -n shop rollout undo deploy/payment       # 롤백 리허설
kubectl -n shop rollout status deploy/payment
# → 롤백 절차·소요 시간을 평시에 몸으로 (새벽에 처음 해보지 않기)
```

**연결 확인** — 배포 마커(09)가 있어야 "최근 배포 있음" 판정이 3초고, GitOps(cncf 14·16)라면 롤백이 Git revert로도 가능합니다 — 완화의 속도는 평시 인프라(마커·리비전·게이트)가 정합니다.

## 4. 서기 훈련 — 타임라인 템플릿

```bash
cat > runbooks/incident-timeline-template.md <<'EOF'
# 사건 타임라인 — <사건명> (SEV-N)
| 시각 | 유형 | 내용 | 행위자 |
|------|------|------|--------|
| 03:02 | 감지 | PaymentBudgetFastBurn page | 알림 |
| 03:05 | 확인 | L1에서 payment 에러율 40% 확인 | @oncall |
| 03:07 | 발견 | 배포 마커 02:50 — v2.3.1 배포 확인 | @oncall |
| 03:09 | 결정 | 롤백 실행 승인 | @ic |
| 03:11 | 조치 | rollout undo 실행 | @oncall |
| 03:18 | 확인 | 에러율 2%로 회복, 알림 resolve | @oncall |
유형: 감지/확인/발견/결정/조치/소통
EOF
```

**의미** — 이 여섯 줄이 포스트모템의 원천이고, "감지→완화 16분"이라는 측정(게임데이의 지표)의 근거입니다. 기억은 아침이면 사라집니다 — 서기(또는 사건 채널의 타임스탬프)가 기록을 남깁니다.

## 5. 정리

```bash
# 클러스터·runbook은 lab-02(게임데이)에서 사용
echo "게임데이는 lab-02에서 — runbook이 시험대에 오른다"
```

## 정리

- runbook 5요소: 의미·즉시 3개·완화 후보(조건→조치)·에스컬레이션(시간 기준)·함정
- "원인 규명은 롤백 후" — 완화 우선이 문서에 박혀야 새벽에 작동합니다
- 사슬 검증: 알림→runbook→대시보드 링크의 무결성 (조용한 끊김은 여기서도)
- 롤백 리허설을 평시에 — 완화의 속도는 준비(마커·리비전)가 정합니다
- **★ runbook은 새벽 3시의 뇌를 대신합니다 — 그 품질이 곧 MTTR입니다**
