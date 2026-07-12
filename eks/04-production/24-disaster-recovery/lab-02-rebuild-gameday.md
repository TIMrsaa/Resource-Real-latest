# Lab 02 — 재건 Game Day: 층마다 스톱워치를 들고

"클러스터를 잃었다"를 선언하고, 4계층 스택을 선언에서 다시 세우며 **층별 시간을 기록**합니다. 공유 클러스터라 1층(클러스터 생성)은 모형으로 치환하되, 시간은 실측 기준(~20분)을 사용합니다 — 나머지 층은 전부 실제로 수행합니다.

## Step 0. 재해 선언 — 그리고 첫 번째 시간

```bash
date +%T    # T0 기록
# 시나리오: 서울 리전 불능. dr-target ns의 서비스를 "새 클러스터"에서 재건하세요.
# 판단 게이트(runbook): 선언 기준 충족? 선언 권한자 승인? — 실전에선 이 단계가 수십 분을 먹습니다
kubectl delete namespace dr-target    # 주 리전 소실의 모형
```

## Step 1. 1층 — 인프라 (모형 + 실측 기준)

실전 명령은 이것이고(02의 선언이 그대로 DR 자산):

```bash
# eksctl create cluster -f cluster-config.yaml --region $DR_REGION   # ~20분 (실행은 모형)
echo "T1: 1층 = 20m (실측 기준값 — pilot light였다면 0m)"
```

> 여기서 멈추고 자문하세요: **cluster-config.yaml이 git에 있는가요?** 애드온·노드그룹·access entries까지 선언돼 있는가(02·11)? — 없다면 1층은 20분이 아니라 "고고학"입니다.

## Step 2. 2층 — 플랫폼 (실제 수행)

새 클러스터에 반드시 깔리는 표준 세트 — 23의 fleet base가 있다면 이 한 번이 전부입니다:

```bash
date +%T    # 2층 시작
# (모형: 같은 클러스터를 "새 클러스터"로 간주 — Velero는 lab-01에서 이미 설치됨을 확인만)
velero backup-location get | grep dr-tokyo    # 새 클러스터라면: velero install + BSL 등록이 이 층
# 테넌트/정책 표준 (34의 패키지 등 — fleet base apply의 모형)
kubectl get ns velero >/dev/null && echo "플랫폼 층 OK"
date +%T    # 2층 종료 — 기록
```

## Step 3. 3층 — 워크로드 (GitOps 재포인팅의 모형)

실전은 "ApplicationSet에 새 클러스터 등록" 한 줄 — 모형은 선언 재적용:

```bash
date +%T
# 무상태 워크로드는 git 선언에서 즉시 부활합니다 (백업이 필요 없습니다!)
kubectl create ns dr-target
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: dr-target
  labels: { app: app }
spec:
  replicas: 1
  selector:
    matchLabels: { app: app }
  template:
    metadata:
      labels: { app: app }
    spec:
      containers:
        - name: podinfo
          image: ghcr.io/stefanprodan/podinfo:6.7.1
EOF
kubectl rollout status deploy/app -n dr-target
date +%T    # 3층 종료
```

✅ 주목 — **무상태는 백업에서 복원하지 않았습니다.** 선언(git)이 원본이니까. 백업이 필요한 것은 선언으로 못 만드는 것들뿐입니다 → 4층.

## Step 4. 4층 — 데이터 (격리 백업에서 복원)

```bash
date +%T
# 도쿄 금고의 dr-copy에서 — Secret 등 "선언 밖 상태"만 골라 복원
velero restore create rebuild --from-backup dr-copy \
  --include-resources secrets --wait
kubectl get secret keys -n dr-target -o jsonpath='{.data.api}' | base64 -d; echo   # dr-drill-2026
date +%T    # 4층 종료
```

✅ 리전을 잃어도 산 백업(lab-01)이 마지막 층을 메웠습니다. 실전의 4층은 여기에 **DB 복제 승격/스냅샷 복원**(크기 비례!)이 더해집니다 — 대개 RTO의 최대 항.

## Step 5. 전환 + 검증 — 그리고 분해표

```bash
date +%T
kubectl exec -n dr-target deploy/app -- wget -qO- localhost:9898/healthz && echo "서비스 헬스 OK"
# 실전: DNS/GA 전환(23) + 합성 트랜잭션 + 관측 스택 확인(12·35의 교훈)
date +%T    # T_end
```

## Step 6. RTO 분해표 (이 모듈의 산출물)

```markdown
# 재건 Game Day #1 — RTO 분해 (T0: __)
| 층 | 실측/기준 | 병목 원인 | 다음 분기 개선 후보 |
|----|----------|----------|--------------------|
| 판단 | (실전 추정 __m) | 선언 기준 모호 | runbook에 선언 기준·권한자 명문화 |
| 1층 인프라 | 20m (기준) | CP 생성 시간 | pilot light 검토 (CP 상시 = -20m, 비용 __) |
| 2층 플랫폼 | __m | | fleet base 커버리지 확대 (23) |
| 3층 워크로드 | __m | | ApplicationSet 등록 자동화 (39) |
| 4층 데이터 | __m | 복원 크기 | 핵심 DB만 노선 B(상시 복제)로 승격 |
| 전환·검증 | __m | DNS TTL | GA 검토 / 합성 체크 자동화 |
| **합계** | __ | | 목표 RTO __ 대비: [ ] 충족 [ ] 미달 |
다음 훈련: +1분기 — 이번에 모형이었던 1층을 실제 임시 클러스터로
```

## 정리

```bash
bash cleanup.sh    # 양 리전 버킷까지 — 격리 백업도 실험이 끝나면 비용입니다
```
