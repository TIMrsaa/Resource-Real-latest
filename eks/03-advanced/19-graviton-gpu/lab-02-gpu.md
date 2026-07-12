# Lab 02 — GPU: 장비가 자원이 되는 순간 (선택 실습)

> ⚠️ **비용 경고**: g5.xlarge ≈ 시간당 $1+ — 이 랩은 30분 안에 끝내고 즉시 삭제합니다. 예산이 없으면 Step 0의 "무비용 경로"로: 명령과 출력 예시를 읽는 것만으로 학습 목표의 80%가 달성되도록 썼습니다.

## Step 0. 무비용 경로 안내

GPU 노드 없이도 할 수 있는 것: Step 3의 manifest 읽기, Step 5의 time-slicing 설정 해부, theory §4~6. GPU 노드가 필요한 것: extended resource 등록의 실관찰(Step 2~4). 선택하세요.

## Step 1. GPU 노드그룹 (드라이버는 AMI에 이미 있습니다)

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
eksctl create nodegroup --cluster $CLUSTER --region $AWS_REGION \
  --name gpu-lab --nodes 1 --node-type g5.xlarge \
  --node-labels lab=gpu --node-ami-family AmazonLinux2023
# GPU 인스턴스 타입이면 eksctl이 NVIDIA 변형 AMI를 선택합니다 — 드라이버 포함 (05의 AMI 이야기)
```

**taint를 즉시** — 비싼 작업실에 일반 수업이 들어오기 전에 (34·17의 그 문법):

```bash
GPUNODE=$(kubectl get nodes -l lab=gpu -o jsonpath='{.items[0].metadata.name}')
kubectl taint node $GPUNODE nvidia.com/gpu=present:NoSchedule
```

## Step 2. 등록 전과 후 — device plugin의 존재 증명

```bash
# 등록 전: GPU가 "있어도 없다"
kubectl get node $GPUNODE -o jsonpath='{.status.capacity}' | python3 -m json.tool | grep -i nvidia || echo "(nvidia 자원 없음!)"

# device plugin 투입 (DaemonSet — GPU taint를 tolerate하며 GPU 노드에만 앉습니다)
kubectl create -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.0/deployments/static/nvidia-device-plugin.yml
sleep 30

# 등록 후
kubectl get node $GPUNODE -o jsonpath='{.status.capacity.nvidia\.com/gpu}'; echo
```

예상: `(없음)` → **`1`**. ✅ **장비가 자원이 된 순간** — 관리인(plugin)이 kubelet에 신고하자 스케줄러의 계산 대상이 됐습니다. 하드웨어가 아니라 **등록**이 스케줄링의 실체입니다.

## Step 3. GPU Pod — 정수 자원의 문법

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: cuda-test }
spec:
  restartPolicy: OnFailure
  tolerations: [{ key: nvidia.com/gpu, operator: Exists, effect: NoSchedule }]
  containers:
  - name: cuda
    image: nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda12.5.0
    resources:
      limits: { nvidia.com/gpu: 1 }        # ★ 정수만, requests=limits 강제
EOF
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/cuda-test --timeout=300s
kubectl logs cuda-test | tail -3
```

예상: `Test PASSED` — 컨테이너 안에서 CUDA가 GPU를 잡아 벡터 덧셈을 돌렸습니다.

## Step 4. 점유의 증명 — 두 번째 손님은 Pending

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: cuda-second }
spec:
  restartPolicy: OnFailure
  tolerations: [{ key: nvidia.com/gpu, operator: Exists, effect: NoSchedule }]
  containers:
  - name: cuda
    image: nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda12.5.0
    resources: { limits: { nvidia.com/gpu: 1 } }
EOF
sleep 10; kubectl get pod cuda-second
kubectl describe pod cuda-second | grep -A2 Events | tail -2
```

예상: `Pending` — `Insufficient nvidia.com/gpu`. (첫 Pod가 Succeeded로 끝났다면 자원이 반납돼 돌 수도 있습니다 — 그것대로 교훈: **점유는 Pod 수명과 함께**.) ✅ CPU와 달리 나눠지지 않는 자원 — 이 엄격함이 다음 Step의 이유입니다.

## Step 5. 공유의 두 길 — 설정으로 읽기 (실행 없이)

```yaml
# time-slicing: device plugin ConfigMap — "1장을 4개로 신고해라"
version: v1
sharing:
  timeSlicing:
    resources:
    - name: nvidia.com/gpu
      replicas: 4        # → capacity가 4로 보임. 단 메모리 격리 없음 — 이웃의 OOM이 나를 뭅니다
```

- time-slicing = **회계만 분할** (가벼운 추론 여럿, 개발용) / MIG = A100/H100급의 **하드웨어 분할** (프로덕션 멀티테넌트)
- Neuron(inf2/trn1)은 문법 동형: neuron device plugin이 `aws.amazon.com/neuron`을 등록 — 단 모델을 Neuron SDK로 컴파일해야 하는 이식 비용과 단가 절감의 거래(theory §6)

## Step 6. 즉시 철수 — GPU의 제1계명

```bash
kubectl delete pod cuda-test cuda-second --ignore-not-found
eksctl delete nodegroup --cluster $CLUSTER --region $AWS_REGION --name gpu-lab --wait
```

✅ idle GPU는 시간당 $1을 태우는 난로입니다 — 실무라면 이 "철수"를 KEDA(15)의 scale-to-zero(큐 기반 워커)나 스케줄 기반 노드 축소로 자동화합니다.

## 정리

```bash
bash cleanup.sh    # device plugin DS, 잔여 노드그룹 확인
```
