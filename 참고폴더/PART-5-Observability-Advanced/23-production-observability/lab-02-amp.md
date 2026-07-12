# Lab 02 — AWS Managed Prometheus (AMP) 연결

> **🌱 AMP 가 뭔가? 왜 쓰나?**
> **AMP (Amazon Managed Prometheus)** = AWS 가 관리하는 Prometheus-호환 메트릭 저장소.
> = 자체 Prometheus HA + Thanos + S3 운영 복잡도를 AWS 가 대신.
>
> **장점**:
> - 자동 HA + 무한 retention (15개월)
> - IAM 인증 (별도 비밀번호 X)
> - PromQL/remote_write 호환 → 기존 Prometheus 그대로
>
> **단점**:
> - 비용 (ingestion + query 별)
> - AWS lock-in
> - 일부 PromQL 제한 (subquery 등)
>
> **언제 선택?** 운영급 메트릭 인프라가 필요하지만 자체 운영 인력이 부족할 때.

## ⚠️ 비용

AMP 는 ingestion + query 별 과금. 학습 1~2시간 ~$0.1 ~ $0.5.

> **🧠 AMP 비용 모델 상세**
> - **Ingestion**: $0.90 / 10M samples (대략, region 마다 다름)
> - **Query**: $0.10 / 1B query samples processed
> - **Storage**: $0.03 / GB / 월
>
> 클러스터당 시계열 50K + 30s scrape = 약 5M samples/h ≈ 120M/일 → 일 $11 ingestion.
> 학습 1~2시간이면 매우 저렴, 운영은 cardinality 절감이 직접 비용 절감.

## 1. AMP Workspace 생성

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2

aws amp create-workspace --alias eks-study --region $REGION

WORKSPACE_ID=$(aws amp list-workspaces --query 'workspaces[?alias==`eks-study`]|[0].workspaceId' --output text --region $REGION)
echo "Workspace: $WORKSPACE_ID"

REMOTE_WRITE_URL="https://aps-workspaces.${REGION}.amazonaws.com/workspaces/${WORKSPACE_ID}/api/v1/remote_write"
QUERY_URL="https://aps-workspaces.${REGION}.amazonaws.com/workspaces/${WORKSPACE_ID}"
```

> **🧠 Workspace 의 의미**
> AMP 의 격리 단위 — 하나의 Prometheus 인스턴스에 해당.
> 권한/저장소/limits 모두 workspace 단위.
>
> 운영 패턴:
> - **환경 분리**: prod / staging / dev 별 workspace
> - **팀 분리**: 보안/네트워크 팀 별 workspace (cross-team 데이터 격리)
> - 같은 region 안에 100개까지 가능

## 2. IRSA 셋업 — Prometheus 가 AMP 에 write

```bash
eksctl create iamserviceaccount \
  --cluster=eks-study \
  --namespace=monitoring \
  --name=amp-iamproxy-ingest-service-account \
  --attach-policy-arn=arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess \
  --override-existing-serviceaccounts \
  --approve --region=$REGION
```

> **🧠 IRSA 흐름 (왜 access key 없이 동작?)**
> 1. K8s ServiceAccount 가 OIDC 토큰 받음 (Pod 시작 시 자동)
> 2. IAM Role 의 trust policy 가 그 OIDC 토큰을 신뢰
> 3. AWS SDK 가 OIDC → STS → 임시 자격 자동 변환
> 4. Pod 가 그 자격으로 AWS API 호출
>
> 결과: **Pod 안에 access key 없음**. 자격 누출 위험 X. (PART-2 의 Module 07 참고)
>
> `AmazonPrometheusRemoteWriteAccess` 정책 = remote_write 만 허용 (read X, admin X).

## 3. Prometheus 의 remote_write 활성화

```bash
helm upgrade kps prometheus-community/kube-prometheus-stack \
  --reuse-values \
  -n monitoring \
  --set "prometheus.prometheusSpec.remoteWrite[0].url=${REMOTE_WRITE_URL}" \
  --set "prometheus.prometheusSpec.remoteWrite[0].sigv4.region=${REGION}" \
  --set "prometheus.serviceAccount.create=false" \
  --set "prometheus.serviceAccount.name=amp-iamproxy-ingest-service-account"
```

`sigv4.region` 으로 AWS Sigv4 인증 자동 처리.

> **🧠 sigv4 인증의 흐름**
> ```
>   Prometheus (IRSA SA)
>     → AWS SDK 가 STS 임시 자격 자동 획득
>     → 모든 remote_write HTTP 요청에 sigv4 서명 추가
>     → AMP endpoint 가 서명 검증 → IAM 권한 확인 → 허가/거부
> ```
>
> sigv4 = AWS 표준 HMAC-SHA256 서명. region/service/timestamp 포함 → replay attack 방지.
> Prometheus 는 SDK 가 알아서 함 → 사용자는 region 만 설정.

## 4. 데이터 흐름 확인

Prometheus 로그:
```bash
kubectl logs -n monitoring prometheus-kps-...-0 -c prometheus --tail=20 | grep -i remote
```

기대: `remote_write` 관련 로그, 401/403 없으면 정상.

> **🧠 흔한 에러와 진단**
> - **401 Unauthorized**: sigv4 서명 실패 → IRSA 미적용? Pod restart 필요? (SA annotation 갱신 후 재시작)
> - **403 Forbidden**: 인증은 됐지만 IAM 권한 부족 → policy 확인 (`AmazonPrometheusRemoteWriteAccess`)
> - **404 Not Found**: workspace ID URL 오타
> - **429 Too Many Requests**: AMP 의 ingestion 한도 초과 → quota 증가 요청 또는 cardinality 절감
> - **timeout**: 네트워크 (NAT Gateway, VPC Endpoint?)
>
> 메트릭 `prometheus_remote_storage_samples_failed_total` 으로 실패 추적.

## 5. AMP 직접 쿼리

```bash
# CLI 로 sigv4 인증 쿼리
curl --aws-sigv4 "aws:amz:${REGION}:aps" \
  --user "$(aws configure get aws_access_key_id):$(aws configure get aws_secret_access_key)" \
  -G "${QUERY_URL}/api/v1/query" \
  --data-urlencode 'query=up' \
  | jq '.data.result | length'
```

기대: 양수 (Prometheus 가 push 한 메트릭).

> **🧠 `--aws-sigv4` curl 옵션**
> curl 7.75+ 부터 sigv4 직접 지원. 형식: `provider1:provider2:region:service`.
> AMP 는 service 명이 `aps` (Amazon Prometheus Service).
>
> 위 명령은 학습용 (access key 사용). 운영에선 STS assumed role 또는 SSO 토큰.

## 6. Grafana 에서 AMP 를 datasource 로 추가

Grafana → Configuration → Data sources → Add data source → Prometheus.

- URL: `${QUERY_URL}`
- Auth: SigV4 (Default region: $REGION)
- Save & test

→ 기존 in-cluster Prometheus + AMP 둘 다 사용 가능.

> **🧠 둘 다 쓰는 운영 패턴**
> - **In-cluster Prom**: 짧은 retention (12h~3d), 빠른 쿼리, 알람 평가
> - **AMP**: 장기 저장 (30d+), 트렌드 분석, 컴플라이언스
>
> Grafana 대시보드:
> - 실시간 알람 / 디버깅 패널 → in-cluster
> - 월간 SLO 리포트, 트렌드 → AMP
>
> Datasource 변수로 토글 가능: `var-datasource = Prometheus | AMP` → 같은 패널 두 데이터 소스 비교.

## 7. Prometheus 자체 retention 줄이기 (AMP 가 장기 저장)

```bash
helm upgrade kps prometheus-community/kube-prometheus-stack \
  --reuse-values \
  -n monitoring \
  --set prometheus.prometheusSpec.retention=12h
```

→ 로컬은 12시간만, AMP 가 15개월. 디스크 절감.

> **🧠 retention 설계 — local vs remote 분담**
> | 데이터 위치 | 기간 | 용도 |
> |-----------|------|------|
> | Local Prometheus | 12h ~ 3d | 알람 평가, 빠른 디버깅 |
> | AMP (long-term) | 30d ~ 15m | 트렌드, SLO 리포트, 컴플라이언스 |
>
> 로컬 짧게 → PVC 작아짐 → 비용 절감 (gp3 100Gi → 20Gi).
> 장기 데이터는 AMP 에 위임 → 운영 부담 감소.
>
> **함정**: 로컬 retention < 알람 윈도우. 알람이 `[7d]` rate 쓰는데 retention 12h 면 평가 불가.
> retention 결정 전 알람 expr 의 가장 긴 윈도우 확인 필수.

## 8. 정리 (학습 끝)

```bash
# remote_write 제거
helm upgrade kps prometheus-community/kube-prometheus-stack \
  --reuse-values \
  -n monitoring \
  --set "prometheus.prometheusSpec.remoteWrite=null"

# AMP workspace 삭제 (비용 정지)
aws amp delete-workspace --workspace-id $WORKSPACE_ID --region $REGION
```

> **🧠 AMP workspace 삭제 = 데이터 영구 소실**
> 백업 옵션 없음. 보존 필요 시 삭제 전 PromQL `/api/v1/query` 로 export → S3 등.
>
> 비용은 데이터 양에 비례 — 30일 동안 안 쓰면 ingestion=0 인데도 storage 비용 누적. 학습 끝나면 삭제.

## 학습 확인

1. AMP 의 retention 은? Prometheus 자체 retention 과의 관계?
2. sigv4 인증의 흐름은?
3. AMP 비용 모델 (어떤 동작이 비용을 만드나)?

> **힌트**:
> 1. AMP=15개월 (조정 가능). 로컬 Prom 은 짧게 (12h~3d), 장기는 AMP 위임 → 디스크 절감. 단 알람 윈도우 < 로컬 retention 필수.
> 2. Pod (IRSA SA) → STS 임시 자격 → 매 요청 sigv4 서명 → AMP 가 서명/IAM 검증.
> 3. (a) Ingestion: 받은 sample 수, (b) Query: 처리한 sample 수, (c) Storage: 보관 GB. cardinality 가 셋 다 영향 — cardinality 절감이 비용 절감.

다음: [lab-03-slo-alerts.md](./lab-03-slo-alerts.md)
