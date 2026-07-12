# Lab 02 — as code 유지·권한·판단

> sidecar가 없는 관리형에서 09의 규율(Git이 진실)을 API·토큰으로 유지하고, 폴더 권한으로 조직을 반영하고, 자체 vs AMG 판단을 정리합니다.

## 0. 준비 (lab-01 이어서)

## 1. 서비스 어카운트 토큰 — API의 열쇠

```bash
# Grafana 서비스 어카운트(사람 아닌 자동화용) 생성 — AMG API 또는 UI
aws grafana create-workspace-service-account --region $REGION \
  --workspace-id $AMG_ID --name ci-dashboards --grafana-role EDITOR 2>/dev/null || \
  echo "UI에서: Administration → Service accounts → Add"

# 토큰 발급 (수명 짧게!)
aws grafana create-workspace-service-account-token --region $REGION \
  --workspace-id $AMG_ID --name ci-token --seconds-to-live 3600 \
  --service-account-id <sa-id> 2>/dev/null || echo "UI에서 토큰 발급"
export GRAFANA_TOKEN=<발급된 토큰>
export AMG_URL=https://$(aws grafana describe-workspace --region $REGION \
  --workspace-id $AMG_ID --query 'workspace.endpoint' --output text)
```

## 2. Git → API push — GitOps의 변형

```bash
# 09의 RED 대시보드 JSON을 API로 배포 (CI가 할 일을 손으로 재현)
cat > /tmp/push-dashboard.sh <<'EOF'
#!/usr/bin/env bash
# CI 스크립트의 원형: Git의 JSON → AMG API
DASH_FILE=$1
curl -s -X POST "$AMG_URL/api/dashboards/db" \
  -H "Authorization: Bearer $GRAFANA_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"dashboard\": $(cat $DASH_FILE), \"overwrite\": true, \"folderUid\": \"\"}"
EOF
chmod +x /tmp/push-dashboard.sh

# 09의 red-dashboard.json(레포에 있다고 가정)을 push
/tmp/push-dashboard.sh /tmp/red-dashboard.json 2>/dev/null || \
  echo '{"uid":"svc-red","title":"Service RED", ...}를 준비해 실행'
# {"status":"success","uid":"svc-red",...}
```

**운영 루프 완성** — 실전에서는 이 스크립트가 CI(GitHub Actions)에 들어갑니다: 대시보드 JSON PR 머지 → CI가 API push → AMG 반영. sidecar(pull)가 push로 바뀌었을 뿐 "Git이 진실, uid 고정"(09)은 그대로입니다. Terraform grafana provider를 쓰면 대시보드·데이터소스·폴더까지 선언 관리로 통합됩니다 — 조직의 IaC 성숙도에 맞춰 선택.

## 3. 폴더·권한 — 조직을 화면에

```
UI(또는 API·Terraform)로:
  폴더 생성: "L1-Overview"(전사 Viewer) / "team-commerce"(팀 Editor) / "sandbox"
  Identity Center 그룹 ↔ Grafana 팀 매핑 → 폴더 권한을 팀에
효과:
  L1(온콜 공용 착지)은 모두가 보되 아무나 못 고침
  팀 폴더는 팀이 자율 (셀프서비스 — 08의 SM, 09의 변수와 같은 정신)
  sandbox는 실험 — 주기 정리 대상
```

## 4. 알림 채널 주의 — Alertmanager와의 역할 정리

```
AMG에도 Grafana Alerting이 있습니다 — 그럼 10의 Alertmanager와 이중?
원칙 정리:
  메트릭 기반 핵심 알림: Prometheus/AMP 룰 + Alertmanager(또는 AMP 관리형)
    → 10·14의 체계 유지 (평가 주체 일원화 — 14의 교훈)
  Grafana Alerting: 보조적(다중 데이터소스 조합 알림 등) 또는 미사용
→ "알림이 두 곳에서 정의되면 정의 분기(08)와 평가 주체 혼선(14)"
  — 어디서 알리는지를 팀 규약으로 명문화
```

## 5. 판단 정리 — 자체 vs AMG

```
시나리오 훈련:
  A. 스타트업 15명, EKS 1개, AMP·CW 사용, SSO는 Google Workspace
     → AMG (SAML로 Google 연동) — 운영 0 + 통합 자동, 15명 과금은 수용 가능
  B. 3,000명 열람하는 사내 포털형 대시보드
     → 자체 (사용자당 과금이 지배적 — Viewer 대량이면 자체가 압도적으로 유리)
  C. 멀티클라우드(AWS+GCP), 데이터소스 절반이 GCP
     → 자체 우세 (AMG의 강점인 AWS 통합이 반감), 단 운영 역량 전제
  D. 금융권, Identity Center 표준, 감사 요구
     → AMG (인증·감사 통합이 결정적)

★ 결정 축의 우선순위: ① SSO·인증 요구 ② 사용자 수(과금) ③ 데이터소스 중심축
  화면은 이식이 쉬우니(JSON) ADR로 남기되 가볍게 재평가 (cncf 48)
```

## 6. SIGNALS-MAP 갱신 (과제)

```
시각화 줄 갱신:
  화면: AMG(Identity Center SSO) — AMP·CW·X-Ray(자리) 데이터소스
  as code: Git → CI가 API push (uid 고정 유지)
  알림 주체: Prometheus/AMP 룰로 일원화 (Grafana Alerting은 보조)
```

## 7. 정리

```bash
bash cleanup.sh   # AMG 워크스페이스 삭제 (사용자당 과금 차단)
rm -f /tmp/push-dashboard.sh
```

## 정리

- 서비스 어카운트 토큰 + API push = 관리형에서의 as code (Git이 진실 불변)
- 폴더=권한 경계, Identity Center 그룹 매핑 — 조직 구조가 화면 권한에
- 알림 정의는 한 곳(Prometheus/AMP 체계)으로 — Grafana Alerting과의 역할 명문화
- 판단 축: SSO 요구 > 사용자 수(과금) > 데이터소스 중심축 — 화면은 이식이 쉬워 결정이 가볍습니다
- **★ 관리형은 서버를 대신 운영하지, 규율(as code·알림 일원화)을 대신 지키지 않습니다**
