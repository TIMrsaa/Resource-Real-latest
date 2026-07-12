# Lab 01 — 워크스페이스·IRSA·remote_write 연결

> AMP 워크스페이스를 만들고, IRSA로 인증을 배선하고, 08의 스택에서 remote_write를 연결해 "수집은 클러스터, 저장은 AMP"의 절단을 실현합니다.

## ⚠️ 비용 주의

AMP 샘플 ingest·저장 요금 발생. 실습 후 cleanup.sh(워크스페이스 삭제) 필수.

## 0. 준비

```bash
export CLUSTER=my-eks
export REGION=ap-northeast-2
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
```

## 1. AMP 워크스페이스 생성

```bash
export WS_ID=$(aws amp create-workspace --region $REGION \
  --alias obs-curriculum --query workspaceId --output text)
echo $WS_ID   # ws-xxxxxxxx

export AMP_ENDPOINT=$(aws amp describe-workspace --region $REGION \
  --workspace-id $WS_ID --query 'workspace.prometheusEndpoint' --output text)
echo $AMP_ENDPOINT
# https://aps-workspaces.ap-northeast-2.amazonaws.com/workspaces/ws-.../
```

## 2. IRSA — 납본 허가증 발급 (eks 파트 지식 재사용)

```bash
# OIDC 공급자 확인 (eks 파트에서 만들었을 것 — 없으면 associate)
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER --region $REGION --approve 2>/dev/null || true

# remote_write 권한의 IAM 롤 + SA를 한 번에 (eksctl IRSA)
eksctl create iamserviceaccount \
  --cluster $CLUSTER --region $REGION \
  --namespace monitoring --name amp-irsa \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess \
  --approve

# 물증 확인: SA에 롤 ARN 어노테이션
kubectl -n monitoring get sa amp-irsa -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
# arn:aws:iam::<account>:role/eksctl-...-amp-irsa
```

## 3. remote_write 연결 — 08의 스택에 한 블록 추가

```bash
# kube-prometheus-stack이 monitoring에 있다고 가정 (없으면 08 방식으로 설치)
cat > /tmp/amp-values.yaml <<EOF
prometheus:
  prometheusSpec:
    serviceAccountName: amp-irsa
    retention: 2h                          # ★ 하이브리드: 로컬은 짧게
    remoteWrite:
      - url: ${AMP_ENDPOINT}api/v1/remote_write
        sigv4:
          region: ${REGION}
        queueConfig:
          maxSamplesPerSend: 1000
          capacity: 2500
          maxShards: 10
EOF
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --reuse-values -f /tmp/amp-values.yaml
kubectl -n monitoring rollout status statefulset/prometheus-monitoring-kube-prometheus-prometheus --timeout=300s
```

**주목** — ServiceMonitor·relabeling·rules는 하나도 안 건드렸습니다. 절단선이 "수집과 저장 사이"라는 것의 실증: 08의 체계 위에 remoteWrite 블록 하나가 얹혔을 뿐입니다.

## 4. 흐름 검증 — 보내는 쪽과 받는 쪽

```bash
# 보내는 쪽: remote_write 큐 메트릭 (자기 관측!)
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
sleep 3
curl -s 'localhost:9090/api/v1/query?query=prometheus_remote_storage_samples_total' | grep -o '"value":\[[^]]*\]' | head -1
# 샘플이 흘러가는 중
curl -s 'localhost:9090/api/v1/query?query=prometheus_remote_storage_samples_failed_total' | grep -o '"value":\[[^]]*\]' | head -1
# 실패 0이어야 (IRSA 문제면 여기서 실패 누적 — 403 로그 확인)
kill %1

# 받는 쪽: AMP에 SigV4 쿼리 (awscurl)
pip install awscurl -q 2>/dev/null || pipx install awscurl 2>/dev/null || true
awscurl --service aps --region $REGION \
  "${AMP_ENDPOINT}api/v1/query?query=up" | head -c 400
# {"status":"success","data":{"result":[{"metric":{"__name__":"up",...}}]}}
# ← ★ 클러스터의 up 메트릭이 AMP에서 조회됩니다 — 절단 성공!
```

## 5. 장애 내성 확인 — 원격이 막히면? (개념 + 관찰 포인트)

```
remote_write의 방어선 (06의 버퍼 물리와 동일 구조):
  AMP 접근 불가(네트워크·권한) 시:
    → WAL + 큐가 완충 (capacity·maxShards)
    → 복구되면 밀린 샘플 배달 (일정 한도 내)
    → 장기 단절이면 드롭 (prometheus_remote_storage_samples_dropped_total)
  감시할 것:
    samples_failed/dropped_total (유실!)
    shards 수·queue 길이 (적체)
  → 06 lab-02와 같은 원리: "보이는 유실, 버티는 버퍼"
  하이브리드의 가치: 단절 중에도 로컬 2h로 조회·알림은 생존
```

## 6. 정리

```bash
rm -f /tmp/amp-values.yaml
# 워크스페이스는 lab-02에서 계속 사용 — 삭제는 cleanup.sh
```

## 정리

- 워크스페이스 생성 → IRSA(eksctl 한 줄) → remoteWrite 블록 — 세 단계로 절단 완성
- 08의 체계(SM·relabel·rules)는 무손실 — 저장만 넘어갔습니다
- 검증 양방향: 보내는 쪽(remote_storage 메트릭) + 받는 쪽(awscurl SigV4 쿼리)
- remote_write도 버퍼의 물리(WAL·큐·드롭) — failed/dropped 감시 필수
- **★ 하이브리드(로컬 2h + AMP 장기)가 실전 기본형 — 단절에도 로컬 알림 생존**
