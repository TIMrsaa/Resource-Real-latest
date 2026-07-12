# Lab 02 — 내가 빌드한 Kubernetes로 클러스터 띄우기

> 빌드 시간이 가장 긴 lab입니다 (이미지 빌드 ~수십 분). 빌드 도는 동안 theory를 복습하거나 모듈 42를 미리 읽는 것을 추천.

## Step 1. 스케줄러에 흔적 심기

이번엔 control plane 컴포넌트를 만집니다 — 스케줄러가 Pod를 바인딩할 때마다 내 로그를 찍게:

```bash
cd ~/go/src/k8s.io/kubernetes
grep -rn "Successfully bound pod to node" pkg/scheduler/ | head -2
```

`pkg/scheduler/schedule_one.go`의 해당 로그 근처에 한 줄 추가:

```go
klog.InfoS("MY-BUILD: scheduling decision made", "pod", klog.KObj(assumedPod), "node", scheduleResult.SuggestedHost)
```

> 모듈 25에서 해부한 그 바인딩 사이클에 내 코드를 꽂는 것입니다 — 이론이 지도가 되는 순간.

## Step 2. kind 노드 이미지 빌드

```bash
kind version    # v0.20+ 권장
time kind build node-image --image kindest/node:my-build ~/go/src/k8s.io/kubernetes
```

> 내부에서 `make quick-release-images`로 전 컴포넌트를 빌드해 노드 이미지에 담습니다. 메모리 부족으로 죽으면: WSL `.wslconfig`에서 memory 상향 후 `wsl --shutdown`.

```bash
docker images | grep my-build    # 이미지 확인
```

## Step 3. 내 이미지로 클러스터 기동

```bash
kind create cluster --name mykube --image kindest/node:my-build
kubectl cluster-info --context kind-mykube
kubectl get nodes -o wide        # VERSION에 -beta/커밋 해시 — 내 빌드!
kubectl version | grep Server
```

✅ **지금 돌고 있는 API 서버/스케줄러/kubelet 전부 내가 컴파일한 것입니다.**

## Step 4. 흔적 확인 — 내 코드가 control plane에서 삽니다

```bash
# Pod 하나 만들어 스케줄링 유발
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: probe
  labels: { run: probe }
spec:
  containers:
    - name: probe
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
EOF
# 스케줄러 로그에서 내 메시지 찾기
kubectl -n kube-system logs -l component=kube-scheduler | grep MY-BUILD
```

예상:
```
... "MY-BUILD: scheduling decision made" pod="default/probe" node="mykube-control-plane"
```

✅ 모듈 25에서 **관측만** 하던 스케줄링 사이클에, 이제 **개입**했습니다. 사용자→관측자→수정자의 마지막 단계.

## Step 5. 기여 루프 정리 (45까지 들고 갈 물건)

```markdown
# K8s 기여 루프 (실측 기록)
1. 수정         어느 파일? (grep으로 찾기: __분)
2. 빌드         make WHAT=... (__분) / kind build node-image (__분)
3. 검증         단위 테스트(초) → 바이너리(분) → kind(수십 분) — 사다리 아래부터!
4. 원복/브랜치   git checkout -- . / git switch -c my-fix
교훈: 사다리 1~2단에서 잡을 수 있는 걸 4단까지 끌고 가지 않기
```

## Step 6. (선택) local-up-cluster — 더 빠른 내부 루프

control plane만 반복 수정할 땐 이미지 빌드 없이:

```bash
# 리눅스 네이티브/WSL2에서 (요구사항 까다로움 — 실패해도 OK, 존재만 알아두기)
# sudo가 필요하고 etcd 바이너리를 요구합니다 (hack/install-etcd.sh)
hack/install-etcd.sh && export PATH=$PATH:$(pwd)/third_party/etcd
sudo -E env PATH=$PATH hack/local-up-cluster.sh
# → 프로세스로 직접 띄운 클러스터. Ctrl-C로 종료
```

빌드 사다리 3단 — kind(4단)보다 한 사이클이 훨씬 빠릅니다. 실제 K8s 개발자들의 주력 루프.

## 정리

```bash
bash cleanup.sh    # mykube 클러스터/이미지 삭제 (소스 리포는 유지)
git -C ~/go/src/k8s.io/kubernetes checkout -- .    # 흔적 코드 원복
```
