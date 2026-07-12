# Lab 02 — KEDA 시식과 개인 종합 지도 작성

층 구분 훈련의 마지막(KEDA는 워크로드, Karpenter는 노드)을 실습으로 확인하고, 지도 트랙의 최종 산출물인 **나의 종합 지도**를 만듭니다.

전제: kind, kubectl, helm.

## Step 1. 클러스터와 KEDA

```bash
kind create cluster --name platform -q

helm repo add kedacore https://kedacore.github.io/charts >/dev/null 2>&1
helm install keda kedacore/keda -n keda --create-namespace >/dev/null
kubectl -n keda rollout status deploy/keda-operator --timeout=180s
kubectl get crd | grep keda | head -3      # ScaledObject, ScaledJob, TriggerAuthentication
```

## Step 2. scale-to-zero — HPA가 못 하는 것

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: worker
  labels: { app: worker }
spec:
  replicas: 0                        # 시작은 0개 — KEDA가 깨울 대상
  selector:
    matchLabels: { app: worker }
  template:
    metadata:
      labels: { app: worker }
    spec:
      containers:
        - name: worker
          image: busybox
          command: ["sh", "-c", "while true; do sleep 5; done"]
EOF

# 크론 트리거로 "특정 시간대에만 뜨는" 워커 (가장 이해하기 쉬운 스케일러)
kubectl apply -f - <<'EOF'
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata: { name: worker-scaler }
spec:
  scaleTargetRef: { name: worker }
  minReplicaCount: 0                 # ★ HPA는 최소 1 — KEDA는 0 가능
  maxReplicaCount: 5
  pollingInterval: 10
  cooldownPeriod: 30
  triggers:
    - type: cron
      metadata:
        timezone: Asia/Seoul
        start: "0 * * * *"           # 매시 정각
        end: "59 * * * *"            # 매시 59분 (실습: 사실상 항상 활성)
        desiredReplicas: "3"
EOF
sleep 30
kubectl get deployment worker
kubectl get hpa                       # ★ KEDA가 내부적으로 HPA를 생성했습니다!
kubectl get scaledobject worker-scaler
```

예상: worker가 0 → 3으로, 그리고 **`keda-hpa-worker-scaler`라는 HPA가 자동 생성**되어 있습니다. ✅ KEDA는 HPA의 대체가 아니라 **전면(front-end)** 입니다 — 외부 이벤트를 HPA가 이해하는 메트릭으로 번역하고, scale-to-zero는 KEDA가 직접 처리합니다(HPA는 최소 1).

## Step 3. 층 구분의 실물 확인

```bash
cat <<'EOF'
지금 일어난 일의 층:
  [워크로드 층] KEDA: 트리거(cron/큐 길이/Kafka lag) → Deployment replicas 조정
                      → Pod가 3개 필요해짐
  [스케줄 층]   스케줄러: 노드에 자리가 있으면 배치, 없으면 Pending
  [노드 층]     Karpenter(eks 17): Pending Pod의 요구를 보고 노드를 만듭니다
★ kind에는 Karpenter가 없으므로 자원이 부족하면 Pod는 Pending에 머뭅니다 —
  "KEDA를 깔았는데 Pod가 안 뜬다"의 원인이 노드 층인 경우가 실무에서 흔합니다
EOF
kubectl get pods -l app=worker -o wide
kubectl describe node kind-platform-control-plane 2>/dev/null | grep -A3 "Allocated resources" | head -5
```

✅ **직렬 관계**를 눈으로: 이벤트 → Pod 수 → (부족하면) 노드 수. "KEDA vs Karpenter"가 왜 성립하지 않는지 몸으로.

## Step 4. 비용 관측 맛보기 — OpenCost (선택)

```bash
helm repo add opencost https://opencost.github.io/opencost-helm-chart >/dev/null 2>&1
helm install opencost opencost/opencost -n opencost --create-namespace \
  --set opencost.prometheus.internal.enabled=false \
  --set opencost.exporter.defaultClusterId=kind >/dev/null 2>&1 || \
  echo "(Prometheus가 필요 — 06의 스택과 함께 쓰는 것이 정상 구성)"

cat <<'EOF'
OpenCost의 위치: 관측(06)의 사촌이되 축이 다릅니다
  메트릭이 "얼마나 빠른가"라면 OpenCost는 "얼마인가"
  네임스페이스·팀·워크로드별 CPU/메모리/스토리지/LB 비용 배분
  → eks의 비용 가드레일이 조직 규모로 확장될 때 (그리고 FinOps 대화의 데이터 원천)
EOF
```

## Step 5. 나의 종합 지도 작성 — 이 트랙의 최종 산출물

```bash
cat > ~/cncf-lab/MY-MAP.md <<'EOF'
# 나의 CNCF 종합 지도 (작성일: ____ / 다음 갱신: ____)

## 1. 우리 스택의 좌표
| 지도 | 축 | 우리가 쓰는 것 | 성숙도·소속 | 리스크 메모 |
|------|-----|---------------|------------|-------------|
| 02 오케스트레이션 | 중심/주변 | K8s (EKS) | Graduated | 배치 스케줄러 없음 |
| 03 런타임 | 층 | containerd + runc | Graduated/OCI | 강화 격리 미도입 |
| 04 네트워킹 | 층·계보 | vpc-cni / CoreDNS / ALB | AWS·Graduated | NetworkPolicy 집행 여부? |
| 05 스토리지 | 역할 | EBS/EFS CSI + Velero | 관리형 | 복원 리허설 주기? |
| 06 관측 | 격자 | ___ | ___ | Grafana 단일 벤더 의존 |
| 07 보안 | 시간선 | ___ | ___ | 런타임 탐지 공백? |
| 08 앱 배포 | 사다리 | Helm+Kustomize / ArgoCD | Graduated | 렌더링 시점 정책? |
| 09 데이터 | 부류·프레임 | RDS(관리형) / ___ | 관리형 | etcd 지표 대시보드? |
| 10 나머지 | 갈래 | KEDA? Karpenter? Harbor? | ___ | 비용 가시성? |

## 2. 공백 (다음 도입 후보, 우선순위)
1. ___
2. ___
3. ___

## 3. 리스크 등록부
- 비CNCF·단일 벤더 의존: ___ (라이선스·상표 리스크 — 01)
- Sandbox 단계인데 프로덕션 핵심 경로: ___ 
- 오퍼레이터 Level 3 미만인데 자체 운영: ___ (백업·복구가 우리 몫)
- 관리형으로 돌아갈 수 없는 지점(데이터 중력): ___

## 4. 판단 순서도 (증상이 올 때)
증상 문장 → 카테고리 → 그 지도의 축으로 층/역할/단 구분 → 후보 2~3
→ 소견서(01의 5종 + 카테고리 특화) → 관리형/자체·추상 높이 → "우리 몫" 명시
→ 결정 + 재검토 시점

## 5. 유지 일정
- 분기: landscape.yml 재집계 (승격·신규·아카이브 diff)
- 연 1회: 스택 각 항목 소견서 갱신
- 사건마다: 사고 카테고리의 지도 재독
EOF

echo "작성 완료: ~/cncf-lab/MY-MAP.md — 빈칸을 채워라 (이것이 지도 트랙의 졸업 과제)"
```

## Step 6. 자가 검증 — 지도를 접었는가

```markdown
# 졸업 체크 (각 문항에 즉답할 수 있는가)
- [ ] "containerd vs runc 뭐가 나아요?" → 왜 성립 안 하는지 30초 설명
- [ ] "Cilium이랑 Istio 중에 뭐요?" → 층 분해 후 조합으로 답
- [ ] "Rook 성능 어때요?" → "Rook-Ceph 말씀이시죠"로 정정
- [ ] "OTel 깔면 관측 되나요?" → 저장·질의가 없다는 경계 설명
- [ ] "admission 정책 있으니 안전?" → 시간선의 공백 지적
- [ ] "Helm이랑 ArgoCD 중에?" → 사다리 단 설명, 함께 씀
- [ ] "Kafka K8s에 올릴까요?" → 판단 프레임 5단계 실행
- [ ] "KEDA vs Karpenter?" → 직렬 관계 설명
★ 여덟 개에 즉답 가능하면, 심층 트랙(11~)으로 갈 준비가 됐습니다
```

## 정리

```bash
bash cleanup.sh
```
