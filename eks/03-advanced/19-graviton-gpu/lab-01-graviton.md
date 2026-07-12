# Lab 01 — Graviton 노드: 번역 사고를 일부러 내고, 제대로 고치기

arm64 노드를 투입하고 — ① 단일 arch 이미지가 깨지는 순간(exec format error), ② multi-arch 이미지가 매끄럽게 도는 이유, ③ 혼합 클러스터의 규칙을 차례로 확인합니다.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. arm 노드 투입 (t4g — Graviton 중 가장 싼 실험체)

```bash
eksctl create nodegroup --cluster $CLUSTER --region $AWS_REGION \
  --name graviton-lab --nodes 1 --node-type t4g.small \
  --node-labels lab=graviton
kubectl get nodes -l lab=graviton -o wide
kubectl get nodes -l lab=graviton -o jsonpath='{.items[0].metadata.labels.kubernetes\.io/arch}'; echo
```

예상: `arm64` — kubelet이 스스로 신고한 아키텍처 label. 스케줄링 어휘의 출발점입니다.

## Step 2. 사고 재현 — 영어책을 한국어 독자에게

amd64 **전용** 이미지를 arm 노드에 강제 배치합니다 (amd64 전용 이미지 예: 오래된 사내 이미지들 — 여기선 amd64 다이제스트를 직접 지정해 재현):

```bash
# nginx의 amd64 판본 다이제스트를 꺼내서 "단일 arch 이미지"를 흉내 냅니다
DIGEST=$(kubectl run skopeo --rm -i --restart=Never --image=quay.io/skopeo/stable -- \
  inspect --raw docker://public.ecr.aws/nginx/nginx:1.27 2>/dev/null \
  | python3 -c "import json,sys; m=json.load(sys.stdin); print([x['digest'] for x in m['manifests'] if x['platform']['architecture']=='amd64'][0])")
echo "amd64 전용 다이제스트: $DIGEST"

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: wrongbook
  labels: { run: wrongbook }
spec:
  nodeSelector: { lab: graviton }
  containers:
    - name: wrongbook
      image: public.ecr.aws/nginx/nginx@$DIGEST    # ← amd64 전용 다이제스트
EOF
sleep 15
kubectl get pod wrongbook
kubectl logs wrongbook 2>&1 | head -2
```

예상:

```
wrongbook   CrashLoopBackOff (또는 Error)
exec /docker-entrypoint.sh: exec format error
```

✅ **`exec format error` — 이 문장을 기억하세요.** 아키텍처 불일치의 시그니처입니다: 이미지 pull은 성공하고(레지스트리는 arch를 안 따집니다), **첫 명령 실행에서** 죽습니다. "이미지도 있고 노드도 Ready인데 CrashLoop"의 단골 정체.

## Step 3. 올바른 책 — multi-arch manifest 검사

```bash
# 같은 태그의 "표지"를 열어봅니다 — 판본 목록
kubectl run skopeo --rm -i --restart=Never --image=quay.io/skopeo/stable -- \
  inspect --raw docker://public.ecr.aws/nginx/nginx:1.27 2>/dev/null \
  | python3 -c "import json,sys; [print(x['platform']['architecture'], x['digest'][:19]) for x in json.load(sys.stdin)['manifests']]"
```

예상: `amd64 …`, `arm64 …` (외 몇 개) — 태그 하나에 판본 여럿. 이제 태그로 배포하면:

```bash
kubectl delete pod wrongbook --ignore-not-found
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: rightbook
  labels: { run: rightbook }
spec:
  nodeSelector: { lab: graviton }
  containers:
    - name: rightbook
      image: public.ecr.aws/nginx/nginx:1.27       # 멀티아치 태그 — 매니페스트 리스트
EOF
sleep 15; kubectl get pod rightbook -o wide    # Running — arm 노드에서!
```

✅ containerd가 자기 arch(arm64)에 맞는 다이제스트를 골라 pull했습니다 — **배포 전 `skopeo inspect`로 판본 확인**이 혼합 클러스터의 백신입니다.

## Step 4. 가격×성능 워크시트 — 전환의 근거 만들기

같은 podinfo를 양쪽 arch에 하나씩 세우고 가볍게 잽니다:

```bash
for arch in amd64 arm64; do
  kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pi-$arch
  labels: { app: pi-$arch }
spec:
  replicas: 1
  selector:
    matchLabels: { app: pi-$arch }
  template:
    metadata:
      labels: { app: pi-$arch }
    spec:
      nodeSelector:
        kubernetes.io/arch: $arch          # 같은 이미지가 양쪽 아치에서 도는지 비교
      containers:
        - name: podinfo
          image: ghcr.io/stefanprodan/podinfo:6.7.1
---
apiVersion: v1
kind: Service
metadata:
  name: pi-$arch
spec:
  selector: { app: pi-$arch }
  ports:
    - port: 9898
EOF
done
kubectl get pods -o wide | grep pi-

for arch in amd64 arm64; do
  echo "=== $arch ==="
  kubectl run vegeta-$arch --rm -i --restart=Never --image=peterevans/vegeta:latest -- sh -c \
    "echo 'GET http://pi-$arch.default.svc:9898/' | vegeta attack -rate=100 -duration=30s | vegeta report | grep -E 'Latencies|Success'"
done
```

워크시트에 채워라 (인스턴스 크기가 다르면 정규화 — 이 랩은 감각용, 정식 비교는 동급 크기로):

```markdown
| | amd64 (t3.small 기준가 __) | arm64 (t4g.small __) |
|---|---|---|
| p99 | | |
| 시간당 단가 | | (대개 ~20% ↓) |
| 단가/성능 판정 | | |
→ 결론: 전환 후보 (근거: 측정치 + 가격표) / 재검증 조건: 부하 프로파일 변경 시
```

## Step 5. 혼합 클러스터 규칙 (산출물)

```markdown
# arm 혼합 운영 규칙
1. CI는 multi-arch 빌드만 (buildx --platform linux/amd64,linux/arm64) — cicd 파트에서 구현
2. 단일 arch 이미지가 남아 있는 동안: 그 워크로드에 arch nodeSelector 강제
3. 배포 전 검사: skopeo inspect로 arm64 판본 존재 확인 (admission으로 강제 가능 — k8s 23)
4. 사이드카/에이전트(모니터링·메시)의 arm 판본까지 전수 확인
5. Karpenter(17) requirements에 arm64 개방은 1~4 완료 후
```

## 정리

```bash
kubectl delete deploy pi-amd64 pi-arm64; kubectl delete svc pi-amd64 pi-arm64
kubectl delete pod rightbook --ignore-not-found
```

graviton-lab 노드그룹은 cleanup.sh가 삭제합니다 (lab-02를 계속 한다면 그 후에).
