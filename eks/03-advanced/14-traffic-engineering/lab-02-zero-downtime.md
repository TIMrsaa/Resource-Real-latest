# Lab 02 — 배포 중 5xx: 재현하고, 해부하고, 0으로

"배포하면 잠깐 에러가 나요"는 감으로 고칠 수 없습니다. **open 모델 부하를 흘리며 배포**해 오류를 세고(대조군), 4종 세트를 장착해 0을 만듭니다(실험군).

전제: lab-01의 loadlab ns + Ingress(ALB). `ALB` 변수 재확보:

```bash
ALB=$(kubectl get ingress podinfo -n loadlab -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

## Step 1. 대조군 — 아무 통제 없는 롤링 배포

터미널 1 — 배포 내내 유입 유지 (13의 open 모델이 심판입니다):

```bash
kubectl run vegeta -n loadlab --image=peterevans/vegeta:latest --restart=Never \
  --requests=cpu=500m -- sh -c \
  "echo 'GET http://$ALB/' | vegeta attack -rate=50 -duration=120s | vegeta report"
```

터미널 2 — 10초 뒤 롤링 트리거 (환경변수 변경 = 새 ReplicaSet):

```bash
kubectl set env deploy/podinfo -n loadlab DEPLOY_MARK=v1
kubectl rollout status deploy/podinfo -n loadlab
```

2분 후 터미널 1의 report에서 기록:

```
Success  [ratio]     __._%          ← 100% 미만이라면: 그 차이가 유저가 본 5xx
Status Codes         200:____  502:__  503:__
```

예상: **502/503이 수십 건** — 원인은 theory §5의 두 사고가 겹친 것: ① 새 Pod가 TG에 등록되기 전에 k8s는 Ready로 간주(입장 비동기) ② 옛 Pod가 deregister 전파 전에 즉사(퇴장 무유예). 앱 코드는 결백합니다.

## Step 2. 4종 세트 장착

```bash
# ① 입장 동기화 — readiness gate 주입 (ns 라벨, 이후 "생성되는" Pod부터 적용)
kubectl label ns loadlab elbv2.k8s.aws/pod-readiness-gate-inject=enabled

# ② 퇴장 유예 + ③ 교체 보폭 — Deployment 패치
kubectl patch deploy podinfo -n loadlab --type=strategic -p '{
  "spec": {
    "strategy": { "rollingUpdate": { "maxSurge": 1, "maxUnavailable": 0 } },
    "template": { "spec": {
      "terminationGracePeriodSeconds": 45,
      "containers": [{ "name": "podinfo",
        "lifecycle": { "preStop": { "sleep": { "seconds": 20 } } } }]
    }}
  }
}'

# ④ 드레이닝 시간 현실화 (기본 300s → 30s: 최장 요청 기준)
kubectl annotate ingress podinfo -n loadlab --overwrite \
  "alb.ingress.kubernetes.io/target-group-attributes=deregistration_delay.timeout_seconds=30"

# 장착 자체가 한 번의 롤링 — 이 판은 측정하지 않습니다 (gate는 새 Pod부터라 아직 반쪽)
kubectl rollout status deploy/podinfo -n loadlab
```

장착 확인 — readiness gate가 실제로 주입됐는지:

```bash
kubectl get pod -n loadlab -l variant=fast -o jsonpath='{.items[0].spec.readinessGates}'; echo
# → [{"conditionType":"target-health.elbv2.k8s.aws/..."}] 형태
kubectl describe pod -n loadlab -l variant=fast | grep -A3 "Readiness Gates"
```

✅ 이제 이 Pod의 Ready에는 **"ALB가 healthy로 판정"이 조건으로 포함**됩니다 — k8s와 ALB의 두 시계가 하나로 묶였습니다.

## Step 3. 실험군 — 같은 측정, 다른 결과

Step 1을 그대로 반복 (vegeta 120s + 10초 뒤 `DEPLOY_MARK=v2`로 재배포):

```bash
kubectl delete pod vegeta -n loadlab --ignore-not-found
# 터미널 1: Step 1의 vegeta 명령 재실행
# 터미널 2: kubectl set env deploy/podinfo -n loadlab DEPLOY_MARK=v2
```

예상 report:

```
Success  [ratio]     100.00%
Status Codes         200:6000
```

✅ **오류 0 — 증명 완료.** 배포 속도가 다소 느려졌음도 관찰하세요(gate 대기 + preStop 20s) — 무중단은 공짜가 아니라 **시간과의 교환**이고, 그 시간은 deregistration_delay·preStop으로 튜닝합니다.

## Step 4. 왜 각 부품이 필요했나 — 하나씩 빼보기 (선택 실험)

시간이 있다면 부품을 하나만 빼고 재측정해보세요. 예측:

| 뺀 것 | 예상 증상 |
|-------|----------|
| readiness gate | 새 Pod 등록 전 옛 Pod 종료 → 순간 healthy 부족(503) |
| preStop sleep | deregister 전파 중 즉사 → 죽은 타깃으로 전송(502) |
| maxUnavailable=0 | 교체 중 용량 자체가 줄어 무릎(13) 근처에서 지연 급등 |
| deregistration 조정 | 오류는 없지만 배포가 replicas×5분으로 |

## Step 5. 산출물 — 무중단 배포 체크리스트

```markdown
# ALB 뒤 서비스 배포 체크리스트
- [ ] ns 라벨: pod-readiness-gate-inject=enabled (target-type ip 필수 짝)
- [ ] preStop sleep 15~30s + tGPS > preStop + 앱 shutdown
- [ ] deregistration_delay = 최장 요청 시간 + 여유 (기본 300s 방치 금지)
- [ ] maxUnavailable=0 (용량 보존) / maxSurge≥1
- [ ] 검증: open 모델 부하 중 배포 → Success 100% (분기마다 재검증)
- [ ] keep-alive: 앱 > ALB idle (502 예방 부등식)
```

## 정리

```bash
bash cleanup.sh    # Ingress 삭제 = ALB 삭제 — 소멸 확인까지 스크립트가 합니다
```
