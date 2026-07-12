# Lab 02 — 지표가 게이트: 자동 분석과 자동 롤백

11의 "사람 판단"을 코드화합니다. 메트릭 분석이 카나리를 자동 승격/롤백하는 것을 보고, 자동화의 품질이 지표 설계에 달렸음을 확인합니다.

전제: lab-01의 Argo Rollouts, pdlab ns.

## Step 1. Prometheus (지표의 원천 — eks 15 재사용)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm install prometheus prometheus-community/prometheus -n monitoring --create-namespace \
  --set alertmanager.enabled=false --set prometheus-pushgateway.enabled=false \
  --set prometheus-node-exporter.enabled=false --set server.persistentVolume.enabled=false 2>/dev/null || true
kubectl -n monitoring rollout status deploy/prometheus-server --timeout=150s
```

## Step 2. AnalysisTemplate — 사람 판단의 코드화

11에서 사람이 "오류율을 보고 판단"하던 것을 successCondition으로:

```bash
cat <<'EOF' | kubectl apply -n pdlab -f -
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata: { name: success-rate }
spec:
  metrics:
    - name: success-rate
      interval: 30s
      count: 4                              # 4번 측정
      successCondition: "result[0] >= 0.90" # 성공률 90% 이상 (eks 13의 SLI)
      failureLimit: 2                        # 2번 미달하면 롤백
      provider:
        prometheus:
          address: http://prometheus-server.monitoring.svc
          query: |
            sum(rate(http_requests_total{namespace="pdlab",status!~"5.."}[1m]))
            /
            sum(rate(http_requests_total{namespace="pdlab"}[1m]))
EOF
echo "✅ '오류율 10% 미만' 판단이 successCondition으로 코드화됨"
```

> 실제 지표는 앱의 /metrics(eks 15)에서 나옵니다. 이 랩은 개념 시연 — podinfo가 노출하는 메트릭 또는 부하 생성으로 근사.

## Step 3. Rollout에 분석 붙이기

```bash
kubectl -n pdlab patch rollout demo --type=merge -p '{
  "spec": { "strategy": { "canary": {
    "steps": [
      { "setWeight": 20 },
      { "analysis": { "templates": [{ "templateName": "success-rate" }] } },
      { "setWeight": 50 },
      { "pause": { "duration": "30s" } },
      { "setWeight": 100 }
    ]
  }}}
}'
echo "이제 20%에서 자동 분석 → 통과하면 확대, 실패하면 롤백"
```

## Step 4. 좋은 버전 — 자동 승격 관찰

```bash
kubectl argo rollouts -n pdlab set image demo app=ghcr.io/stefanprodan/podinfo:6.7.2 2>/dev/null || \
  kubectl -n pdlab patch rollout demo --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/image","value":"ghcr.io/stefanprodan/podinfo:6.7.2"}]'

# AnalysisRun 관찰
for i in $(seq 1 10); do
  echo "=== $(date +%T) ==="
  kubectl -n pdlab get analysisrun -o custom-columns='NAME:.metadata.name,STATUS:.status.phase' 2>/dev/null | tail -2
  kubectl -n pdlab get rollout demo -o jsonpath='phase={.status.phase} weight={.status.canary.weights.canary.weight}{"\n"}' 2>/dev/null
  sleep 20
done
```

예상: AnalysisRun이 `Running` → `Successful`, 카나리가 자동으로 20% → 50% → 100%. ✅ **사람 없이 지표가 승격을 결정**했습니다 — 11의 "관찰 후 확대"가 완전 자동화.

## Step 5. 나쁜 버전 — 자동 롤백

이제 성공률을 떨어뜨리는 버전으로:

```bash
# 부하 + 에러 유발로 성공률 하락 시뮬 (또는 나쁜 이미지)
kubectl -n pdlab patch rollout demo --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/command","value":["./podinfo","--port=9898","--random-error=true"]}]' 2>/dev/null
kubectl argo rollouts -n pdlab set image demo app=ghcr.io/stefanprodan/podinfo:6.7.1 2>/dev/null || true

# 부하 생성 (분석이 트래픽을 봐야 하므로)
kubectl run load -n pdlab --image=peterevans/vegeta:latest --restart=Never -- sh -c \
  'echo "GET http://demo/" | vegeta attack -rate=50 -duration=120s > /dev/null' 2>/dev/null &

for i in $(seq 1 10); do
  echo "=== $(date +%T) ==="
  kubectl -n pdlab get analysisrun -o custom-columns='NAME:.metadata.name,STATUS:.status.phase' 2>/dev/null | tail -1
  P=$(kubectl -n pdlab get rollout demo -o jsonpath='{.status.phase}' 2>/dev/null)
  echo "rollout phase: $P"
  [ "$P" = "Degraded" ] && { echo "🚨 분석 실패 → 자동 롤백!"; break; }
  sleep 20
done
kubectl -n pdlab get rollout demo -o jsonpath='{.status.phase}{"\n"}'
```

예상: AnalysisRun이 `Failed`(성공률 90% 미달), Rollout이 자동 abort되어 stable로 복귀. ✅ **사람이 알람을 보고 반응하는 시간이 제거**됐습니다 — 01 DORA의 복구 시간(MTTR)이 초 단위로.

## Step 6. 지표 설계의 함정 (theory §6 — 자동화의 품질)

```markdown
# AnalysisTemplate 지표 설계 체크 (11 사고 사례의 교훈)
- [ ] 사용자 영향 직결 지표? (성공률·p99 — eks 13, CPU 아님 — eks 15)
- [ ] 카나리 vs stable 비교? (절대값은 배포 무관 변동에 속음)
- [ ] 충분한 트래픽? (5%가 초당 1요청이면 통계 무의미 → count/interval 조정)
- [ ] 다중 지표? (성공률만 보면 지연 폭발 놓침 — 11의 세션 파싱은 4xx였습니다)
- [ ] 지표 지연? (5분 집계면 카나리가 이미 100% — interval을 짧게)

# 자동화가 나쁜 배포를 통과시키는 경우
- 지표가 사용자 경험을 반영 못 함 (5xx만 보고 4xx 무시 → 11의 사고)
- 트래픽 부족으로 통계 무의미
- 임계값이 느슨 (95%가 아니라 50%)
```

## Step 7. Flagger 비교 (개념)

```markdown
# Argo Rollouts vs Flagger (14/15 도구 선택과 짝)
| | Argo Rollouts | Flagger |
|---|---|---|
| 대상 | Rollout CRD(Deployment 교체) | Canary CRD(기존 Deployment 감쌈) |
| 생태계 | ArgoCD(14) | Flux(15) |
| 분석 | AnalysisTemplate | MetricTemplate |
| 마이그레이션 | Deployment → Rollout 수정 필요 | Deployment 유지, 얹기만 |
→ GitOps 도구(14 ArgoCD / 15 Flux)와 짝지어 선택
```

## Step 8. 산출물 — Progressive Delivery 설계

```markdown
# Progressive Delivery 도입
## 무엇이 합류했나 (이 커리큘럼의 매듭)
- 11 카나리 + 14/15 GitOps + eks13 SLI + eks15 메트릭 → 자동 안전 배포

## 설계
- 도구: Rollouts(ArgoCD면) / Flagger(Flux면)
- 트래픽: ALB(eks14) 또는 Istio(eks20) — 정밀 % 필요 시
- 분석 지표: 성공률 + p99 지연(다중), 카나리 vs stable 비교, 충분한 트래픽
- 단계: 5→20→50→100, 각 단계 분석
- 자동 롤백: failureLimit 도달 시 (MTTR 초 단위)

## 사람의 자리 (루프 밖)
- 지표 설계·임계값 결정 (자동화의 품질)
- 분석 실패 시 근본 원인 조사
- "무엇을 측정 안 하는가"의 사각 점검 (11 사고)

## DORA 효과 (01)
- 변경 실패율↓(나쁜 배포 자동 차단), 복구시간↓(자동 롤백), 배포빈도↑(안전하니)
```

## Step 9. 고급 진도

```markdown
17 → Progressive Delivery: 11+14+15+eks13가 하나로 (안전 자동화의 완성)  [ ]
→ 18(커스텀 액션 개발), 19(BuildKit 심층), 20(모노레포 CI)
```

## 정리

```bash
bash cleanup.sh
```
