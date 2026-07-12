# Lab 01 — 빌드하고, 돌리고, 결정을 엿보기

Karpenter를 소스에서 빌드해 **로컬 프로세스로** 실행하고, 실제 클러스터의 Pending Pod에 반응하는 것을 관찰합니다. 17에서 블랙박스였던 "왜 이 타입?"이 로그로 열립니다.

## Step 1. 두 저장소 클론과 구조 확인

```bash
mkdir -p ~/kp && cd ~/kp
gh repo clone kubernetes-sigs/karpenter core
gh repo clone aws/karpenter-provider-aws aws

# 국경 확인 — CloudProvider 인터페이스 (theory §1)
grep -n "type CloudProvider interface" -A 12 core/pkg/cloudprovider/types.go

# 그 구현부
grep -n "func (c \*CloudProvider)" aws/pkg/cloudprovider/cloudprovider.go | head
```

✅ 코어의 인터페이스 선언과 AWS의 구현이 나란히 보입니다 — 이 대응이 두 저장소를 읽는 지도입니다.

## Step 2. 핵심 알고리즘 파일 열기 (읽기 훈련 — 42의 방법)

```bash
cd ~/kp/core
# 시뮬레이터의 진입점
grep -n "func (s \*Scheduler) Solve" -A 25 pkg/controllers/provisioning/scheduling/scheduler.go | head -35

# requirements 교집합 대수 — "타입 집합"이 좁혀지는 곳
grep -n "func (r Requirements) Intersects\|func (r Requirements) Add" pkg/scheduling/requirements.go
```

읽는 법: 17에서 우리가 "requirements를 넓게 열어라"라고 배운 이유가 여기 있습니다 — Solve는 Pod 요구와 NodePool requirements를 교집합해 남은 타입 집합을 Fleet에 넘깁니다. 집합이 크면 선택지가 큽니다.

## Step 3. 빌드 (Go 툴체인)

```bash
cd ~/kp/aws          # 실행 가능한 바이너리는 프로바이더 쪽
go version           # 1.23+
make vet             # 정적 검사
go build ./...       # 컴파일 확인 (첫 회는 의존성 다운로드로 수 분)
```

> 코어를 수정하며 개발하려면 `go.mod`에 replace 지시자로 로컬 코어를 가리킵니다:
> ```bash
> go mod edit -replace sigs.k8s.io/karpenter=../core
> go build ./... && git diff go.mod    # 확인 후 PR 전엔 반드시 되돌릴 것!
> ```
> 이 한 줄이 "코어를 고치며 AWS 프로바이더로 실험"을 가능케 합니다 — 그리고 PR에 실수로 포함되는 단골 사고입니다(pitfalls).

## Step 4. 로컬 실행 — 클러스터의 컨트롤러를 내 노트북으로

클러스터에 이미 설치된 Karpenter(17)가 있다면 **먼저 끕니다**(두 컨트롤러가 같은 NodeClaim을 두고 경쟁하면 안 됩니다):

```bash
kubectl scale deploy/karpenter -n karpenter --replicas=0
```

로컬 실행 (컨트롤러는 kubeconfig로 클러스터에 접속하고, AWS는 로컬 자격증명 사용):

```bash
cd ~/kp/aws
export CLUSTER_NAME=k8s-study
export AWS_REGION=ap-northeast-2
export KARPENTER_SERVICE=karpenter
export DISABLE_WEBHOOK=true
export LOG_LEVEL=debug              # ★ 결정 과정을 보려면 필수

go run ./cmd/controller 2>&1 | tee /tmp/karpenter-local.log
```

✅ 이제 클러스터의 Pending Pod를 **내 노트북의 프로세스**가 처리합니다 — 브레이크포인트를 걸 수도 있고(dlv), 코드를 고쳐 재시작할 수도 있습니다. 개발 루프가 초 단위가 됩니다.

## Step 5. 결정 엿보기 — "왜 이 타입인가"

다른 터미널에서 17의 그 워크로드를 띄웁니다:

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: inflate }
spec:
  replicas: 3
  selector: { matchLabels: { app: inflate } }
  template:
    metadata: { labels: { app: inflate } }
    spec:
      tolerations: [{ key: lab, value: karpenter, effect: NoSchedule }]
      nodeSelector: { karpenter.sh/nodepool: lab }
      containers:
      - name: pause
        image: public.ecr.aws/eks-distro/kubernetes/pause:3.10
        resources: { requests: { cpu: "1" } }
EOF
```

로컬 로그에서 추적할 것:

```bash
grep -iE "found provisionable pod|computed new nodeclaim|instance types|launched" /tmp/karpenter-local.log | head -20
```

읽는 순서 (theory §4의 파이프라인이 로그로):

1. `found provisionable pod(s)` — Pending 감지
2. `computed new nodeclaim(s) to fit pod(s)` — 시뮬레이션 결과(가상 노드 몇 개, 각각 어떤 요구)
3. **인스턴스 타입 후보 개수** — 여기가 핵심: requirements가 좁으면 이 숫자가 작습니다
4. `launched nodeclaim` — Fleet 낙찰 결과(실제 타입·존·capacity-type)

✅ 실험: NodePool의 requirements에서 `instance-category`를 `[c]`로 좁힌 뒤 같은 로그를 보라 — 후보 수가 급감하고, 낙찰 타입이 더 비싸지거나 실패할 수 있습니다. **17의 "네거티브 설계" 조언이 로그 한 줄로 증명됩니다.**

## Step 6. 디버거로 한 걸음씩 (선택)

```bash
go install github.com/go-delve/delve/cmd/dlv@latest
dlv debug ./cmd/controller -- 2>&1
# (dlv) break sigs.k8s.io/karpenter/pkg/controllers/provisioning/scheduling.(*Scheduler).Solve
# (dlv) continue    → Pending Pod가 생기면 멈춥니다
```

Solve 안에서 `pods`, `instanceTypes` 슬라이스를 들여다보면 — 시뮬레이터가 무엇을 보고 있는지 그대로 보입니다.

## 정리

```bash
# 로컬 컨트롤러 종료 (Ctrl-C) 후, 클러스터 컨트롤러 복구
kubectl scale deploy/karpenter -n karpenter --replicas=1
kubectl delete deploy inflate --ignore-not-found
```

⚠️ **replace 지시자를 되돌렸는지 확인**: `git diff go.mod` — lab-02의 PR에 섞이면 안 됩니다.
