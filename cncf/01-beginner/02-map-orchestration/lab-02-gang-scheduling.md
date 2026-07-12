# Lab 02 — 기본 스케줄러의 한계 재현과 갱 스케줄링 시식

"왜 배치 스케줄러 카테고리가 존재하는가"를 데드락 재현 → Volcano 갱 스케줄링으로 확인합니다.

전제: kind, kubectl, helm. 메모리 8GB 권장.

## Step 1. 자원이 빠듯한 클러스터 준비

```bash
kind create cluster --name sched --config - <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: worker
  - role: worker
EOF
kubectl describe node sched-worker | grep -A2 "Allocatable" | head -4
```

## Step 2. 상호 굶김 재현 — Pod 단위 스케줄링의 함정

워커 4개가 전부 떠야 하는 "분산 잡" 둘을, 합치면 자원을 초과하게 던집니다:

```bash
for JOB in alpha beta; do
kubectl create -f - <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: train-$JOB }
spec:
  serviceName: train-$JOB
  replicas: 4
  selector: { matchLabels: { job: $JOB } }
  template:
    metadata: { labels: { job: $JOB } }
    spec:
      containers:
        - name: worker
          image: busybox
          command: ["sh","-c","echo waiting for all workers...; sleep 3600"]
          resources: { requests: { cpu: "700m" } }   # 노드당 2~3개만 수용 가능하게
EOF
done
sleep 30
kubectl get pods -o wide | grep train | sort
```

예상: alpha 2~3개 Running + 나머지 Pending, beta도 2~3개 Running + Pending — **양쪽 다 "일부만" 떠서 자원을 점유한 채, 서로의 나머지를 기다리는 상태**. 분산 학습이라면 둘 다 한 스텝도 진행 못 하면서 클러스터는 만석입니다. ✅ 기본 스케줄러는 각 Pod 배치에서 완벽히 옳았습니다 — 문제는 **잡 단위 원자성**이라는 개념 자체가 없다는 것(theory §3).

```bash
kubectl delete statefulset train-alpha train-beta
```

## Step 3. Volcano 설치 — 갱 스케줄러 투입

```bash
helm repo add volcano-sh https://volcano-sh.github.io/helm-charts >/dev/null 2>&1
helm install volcano volcano-sh/volcano -n volcano-system --create-namespace >/dev/null
kubectl -n volcano-system wait --for=condition=ready pod --all --timeout=180s
kubectl get crd | grep volcano | head -4        # PodGroup, Queue, VolcanoJob ...
```

## Step 4. 같은 상황, 갱 스케줄링으로

```bash
for JOB in alpha beta; do
kubectl create -f - <<EOF
apiVersion: batch.volcano.sh/v1alpha1
kind: Job
metadata: { name: gang-$JOB }
spec:
  schedulerName: volcano
  minAvailable: 4                     # ★ 갱: 4개 전부 배치 가능할 때만 시작
  queue: default
  tasks:
    - replicas: 4
      name: worker
      template:
        spec:
          containers:
            - name: worker
              image: busybox
              command: ["sh","-c","echo all-or-nothing!; sleep 120"]
              resources: { requests: { cpu: "700m" } }
          restartPolicy: Never
EOF
done
sleep 30
kubectl get pods | grep gang | sort
kubectl get podgroup | head -5
```

예상: **한 잡은 4/4 전부 Running, 다른 잡은 0/4 전부 Pending**(PodGroup이 Inqueue/Pending) — 반쪽 진입이 사라졌습니다. 앞 잡이 끝나면(120s) 뒤 잡이 4개 동시에 시작됩니다:

```bash
sleep 120
kubectl get pods | grep gang | sort
```

✅ **all-or-nothing이 상호 굶김을 구조적으로 제거** — Pod 단위 최적화(기본)와 잡 단위 원자성(갱)은 다른 층의 문제였습니다. Kueue라면 같은 문제를 "잡을 큐에서 대기시키는" 수문장 방식으로 풉니다(스케줄러 교체 없이) — 층의 차이를 기억하세요.

## Step 5. 산출물 — 카테고리 존재 증명 카드

```markdown
# 오늘 확인한 것
- 기본 스케줄러: Pod 단위 결정 — 각 결정은 옳지만 잡 원자성 개념이 없음
- 재현: 잡 2개가 서로 절반씩 점유 → 전체 진행 0 (Step 2)
- 갱(Volcano): minAvailable=4 → 전부 아니면 대기 → 순차 완주 (Step 4)
- 처방 층위: 스케줄러 대체(Volcano) vs 수락 제어(Kueue) — 병용 가능
- 실무 신호: "GPU 클러스터가 만석인데 아무 잡도 안 끝난다" → 이 카테고리로
```

## 정리

```bash
bash cleanup.sh
```
