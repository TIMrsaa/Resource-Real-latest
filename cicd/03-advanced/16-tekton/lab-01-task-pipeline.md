# Lab 01 — Task/Pipeline이 Pod가 되는 것을 보다

Tekton을 설치하고 CI 파이프라인을 CRD로 만든 뒤, 각 Task가 Pod로, step이 컨테이너로 실행되는 것을 관찰합니다. CI가 완전히 쿠버네티스가 되는 지점.

```bash
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
```

## Step 1. Tekton 설치

```bash
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
kubectl -n tekton-pipelines rollout status deploy/tekton-pipelines-controller --timeout=120s

# tkn CLI (https://github.com/tektoncd/cli)
tkn version 2>/dev/null || echo "tkn 설치 권장"
```

✅ tekton-pipelines-controller가 k8s 30의 Operator 패턴 — TaskRun/PipelineRun CRD를 watch하며 Pod를 만듭니다(14 ArgoCD, eks 17 Karpenter와 같은 구조).

## Step 2. Task — 재사용 단위 (steps = 컨테이너)

```bash
kubectl create ns tektonlab
cat <<'EOF' | kubectl apply -n tektonlab -f -
apiVersion: tekton.dev/v1
kind: Task
metadata: { name: build-test }
spec:
  params:
    - name: message
      default: "hello"
  steps:
    - name: compile                    # ← 컨테이너 1
      image: golang:1.23-alpine
      script: |
        echo "[compile] $(params.message)"
        echo 'package main; func main(){println("built")}' > /workspace/main.go
        cd /workspace && go build -o app main.go && echo "빌드 완료"
    - name: test                       # ← 컨테이너 2 (같은 Pod, 볼륨 공유)
      image: golang:1.23-alpine
      script: |
        echo "[test] 앞 step이 만든 파일이 보이나요?"
        ls -la /workspace/app && echo "✅ step 간 볼륨 공유 (03의 잡 내 스텝과 동형)"
EOF
```

## Step 3. TaskRun — 실행하면 Pod가 뜹니다

```bash
cat <<'EOF' | kubectl apply -n tektonlab -f -
apiVersion: tekton.dev/v1
kind: TaskRun
metadata: { name: build-test-run }
spec:
  taskRef: { name: build-test }
  params: [{ name: message, value: "from tekton" }]
EOF

# Pod가 뜨는 것을 관찰
kubectl -n tektonlab get pods -w &
WATCH=$!
sleep 40; kill $WATCH 2>/dev/null

# 결과
kubectl -n tektonlab get taskrun build-test-run -o jsonpath='{.status.conditions[0].reason}'; echo
kubectl -n tektonlab logs -l tekton.dev/taskRun=build-test-run --all-containers --prefix 2>/dev/null | tail -8
```

예상: TaskRun이 Pod를 만들고(step마다 컨테이너), `Succeeded`. ✅ **CI 실행이 완전히 K8s Pod**입니다 — `kubectl get pods`로 CI가 보이고, k8s의 모든 도구(리소스 제한, 노드 선택, 보안)가 적용됩니다(theory §2).

## Step 4. Pod 구조 확인 — step = 컨테이너

```bash
POD=$(kubectl -n tektonlab get pods -l tekton.dev/taskRun=build-test-run -o jsonpath='{.items[0].metadata.name}')
kubectl -n tektonlab get pod $POD -o jsonpath='{range .spec.containers[*]}{.name}{"\n"}{end}'
```

예상: `step-compile`, `step-test` (+ Tekton의 init/sidecar 컨테이너). ✅ **각 step이 컨테이너**이고, 같은 Pod라 `/workspace` 볼륨을 공유합니다 — 03의 "같은 잡의 스텝은 파일 공유"가 Tekton에선 "같은 Pod의 컨테이너"로.

## Step 5. Pipeline — Task들의 조합

```bash
# 재사용 Task: git-clone (Tekton Hub 스타일 — 여기선 간단 버전)
cat <<'EOF' | kubectl apply -n tektonlab -f -
apiVersion: tekton.dev/v1
kind: Task
metadata: { name: fetch-source }
spec:
  workspaces: [{ name: output }]
  steps:
    - name: clone
      image: alpine/git
      script: |
        echo "소스 가져오기 (실제로는 git clone)"
        echo "print('app')" > $(workspaces.output.path)/app.py
        echo "✅ workspace에 소스 배치"
---
apiVersion: tekton.dev/v1
kind: Task
metadata: { name: run-tests }
spec:
  workspaces: [{ name: source }]
  steps:
    - name: test
      image: python:3.12-alpine
      script: |
        echo "앞 Task가 workspace에 놓은 소스:"
        cat $(workspaces.source.path)/app.py && echo "✅ Task 간 workspace 공유"
---
apiVersion: tekton.dev/v1
kind: Pipeline
metadata: { name: ci }
spec:
  workspaces: [{ name: shared }]
  tasks:
    - name: fetch
      taskRef: { name: fetch-source }
      workspaces: [{ name: output, workspace: shared }]
    - name: test
      taskRef: { name: run-tests }
      runAfter: [fetch]                    # ← 의존 (Actions needs)
      workspaces: [{ name: source, workspace: shared }]
EOF
```

## Step 6. PipelineRun — 워크스페이스로 데이터가 흐릅니다

```bash
cat <<'EOF' | kubectl apply -n tektonlab -f -
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata: { name: ci-run }
spec:
  pipelineRef: { name: ci }
  workspaces:
    - name: shared
      emptyDir: {}                         # 또는 PVC (지속성 필요 시)
EOF
sleep 50
kubectl -n tektonlab get pipelinerun ci-run -o jsonpath='{.status.conditions[0].reason}'; echo
kubectl -n tektonlab logs -l tekton.dev/pipelineRun=ci-run --all-containers 2>/dev/null | grep -E "workspace|✅" | head
```

예상: fetch Task가 workspace에 소스를 놓고, test Task가 그것을 읽음. ✅ **Task 간 데이터가 Workspace(볼륨)로 흐릅니다**(theory §3) — 03의 잡 간 artifacts에 대응하되 볼륨 기반.

## Step 7. 매핑 확인 (산출물)

```markdown
# Tekton ↔ 앞 도구들 (12의 이식성 최종)
| Tekton | Actions | Jenkins | 내가 만든 것 |
|--------|---------|---------|-------------|
| Task | composite action | Shared Library | build-test, fetch-source |
| step | step | sh | compile, test |
| Pipeline | workflow | pipeline | ci |
| PipelineRun | workflow run | build | ci-run |
| Workspace | artifacts | archive | shared (emptyDir) |
| runAfter | needs | 의존 | fetch→test |
→ 결정적 차이: Task/Pipeline이 클러스터 리소스(kubectl로 관리), 실행이 Pod
```

## 정리

lab-02에서 Triggers와 선택 기준을 다룹니다.
