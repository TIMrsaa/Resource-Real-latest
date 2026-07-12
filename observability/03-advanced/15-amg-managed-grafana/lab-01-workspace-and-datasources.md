# Lab 01 — 워크스페이스·인증·데이터소스 3종 배선

> AMG 워크스페이스를 만들고 AMP·CloudWatch 데이터소스를 IAM으로 배선해, 13~14의 데이터가 관리형 화면에 나타나게 합니다. (X-Ray 배선은 17에서 데이터가 생기면 완성.)

## ⚠️ 비용 주의

AMG는 활성 사용자당 과금(로그인해야 과금되는 구조지만 방치 금지). 실습 후 워크스페이스 삭제.

## 0. 전제

- 14의 AMP 워크스페이스(데이터가 흐르는 중이면 이상적 — 아니면 재연결)
- IAM Identity Center 활성화(조직에서 이미 쓰면 그대로, 아니면 활성화 필요 — 콘솔)

## 1. 워크스페이스 생성

```bash
export REGION=ap-northeast-2

# 서비스 롤 자동 생성 + Identity Center 인증으로 생성 (CLI 예시)
aws grafana create-workspace --region $REGION \
  --workspace-name obs-curriculum \
  --account-access-type CURRENT_ACCOUNT \
  --authentication-providers AWS_SSO \
  --permission-type SERVICE_MANAGED \
  --workspace-data-sources PROMETHEUS CLOUDWATCH XRAY

export AMG_ID=$(aws grafana list-workspaces --region $REGION \
  --query "workspaces[?name=='obs-curriculum'].id" --output text)
aws grafana describe-workspace --region $REGION --workspace-id $AMG_ID \
  --query 'workspace.{status:status,endpoint:endpoint}'
# status ACTIVE 대기 → endpoint가 접속 URL
```

**주목** — `--workspace-data-sources`에 선언한 것에 맞춰 서비스 롤 권한이 구성됩니다: AMP·CW·X-Ray 읽기가 IAM으로 — 어디에도 키를 넣지 않습니다.

## 2. 사용자 할당 (Identity Center)

```bash
# Identity Center 사용자를 Admin으로 할당 (사용자 ID는 Identity Center에서 확인)
aws grafana update-permissions --region $REGION --workspace-id $AMG_ID \
  --update-instruction-batch '[{
    "action": "ADD",
    "role": "ADMIN",
    "users": [{"id": "<identity-center-user-id>", "type": "SSO_USER"}]
  }]'
# 콘솔에서 하는 것이 더 간단: AMG 워크스페이스 → 사용자 할당
```

브라우저로 endpoint 접속 → Identity Center 로그인 → Grafana 화면. **관찰**: 로컬 admin 계정이 없습니다 — 처음부터 SSO가 유일한 문입니다(자체 Grafana에서 몇 주 걸리는 통합이 기본값).

## 3. 데이터소스 배선 ① — AMP (SigV4 자동)

AMG UI: Connections → Data sources → Add → Amazon Managed Service for Prometheus

```
Region 선택 → 14의 워크스페이스가 드롭다운에 → 선택 → Save & Test
"Data source is working"
→ 배선 끝. SigV4 서명·엔드포인트가 자동 — 12에서 손으로 하던 URL·인증
  설정이 IAM 통합으로 접힙니다
```

Explore에서 확인: `up` 쿼리 → 클러스터의 타깃들이 관리형 화면에. 09에서 만든 RED 대시보드 JSON을 Import하면 그대로 동작합니다(datasource만 AMP로) — **화면 문법의 이식성** 확인.

## 4. 데이터소스 배선 ② — CloudWatch

Add → CloudWatch → 기본 인증(워크스페이스 IAM 롤) → Save & Test

```
Explore에서:
  Metrics: ContainerInsights 네임스페이스 → pod_cpu_utilization (13의 그것)
  Logs: /aws/containerinsights/.../application 선택 →
    Logs Insights 쿼리를 Grafana 안에서!
    fields @timestamp, log_processed.event | filter log_processed.event = "pg_timeout"
→ 13에서 콘솔로 하던 조사가 Grafana 한 화면으로 — 메트릭(AMP) 옆에
  로그(CW)가 나란히 (12의 상관 화면이 AWS 부품으로 절반 재현)
```

## 5. 데이터소스 배선 ③ — X-Ray (자리만)

Add → X-Ray → IAM 롤 인증 → Save & Test. 아직 트레이스 데이터가 없습니다(17에서 ADOT가 공급) — 배선만 확인하고 17에서 되돌아옵니다. 17을 마치면 "AMP 그래프 → X-Ray 트레이스 → CW 로그"의 AWS판 상관 동선이 완성됩니다.

## 6. 정리

```bash
# 워크스페이스는 lab-02에서 계속 — 삭제는 cleanup.sh
echo "as code·권한은 lab-02에서"
```

## 정리

- 워크스페이스 생성 시 데이터소스 선언 → 서비스 롤 권한 자동 — 키 없는 배선
- 인증은 처음부터 Identity Center — 로컬 계정 없음 (SSO가 기본값)
- AMP(SigV4 자동)·CW(Logs Insights를 Grafana 안에서)·X-Ray(자리) 3종 배선
- 09의 대시보드 JSON이 그대로 Import — 화면 문법의 이식성
- **★ AMG의 실체 = Grafana + IAM 통합 — 화면은 아는 것, 새로 배울 것은 자격의 흐름뿐**
