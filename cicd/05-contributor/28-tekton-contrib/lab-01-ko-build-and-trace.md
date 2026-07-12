# Lab 01 — ko로 빌드·배포하고, TaskRun이 Pod가 되는 순간을 추적

19의 ko와 16의 Tekton이 합류합니다 — 소스에서 컨트롤러를 빌드해 kind에 얹고, reconcile 경로에 내 로그를 심습니다.

전제: Go 1.23+, ko, kind, kubectl. 메모리 8GB 권장.

## Step 1. 클러스터와 클론

```bash
kind create cluster --name tekton-dev -q
mkdir -p ~/contrib && cd ~/contrib
git clone --depth 50 https://github.com/tektoncd/pipeline.git && cd pipeline

# 코드 지도 확인 (theory §2)
ls pkg/reconciler/                      # taskrun, pipelinerun ...
grep -n "func MakePod\|func.*Pod" pkg/reconciler/taskrun/resources/pod.go | head -3
ls cmd/entrypoint/                      # 스텝 순차 실행의 비밀 (theory §3)
```

## Step 2. ko 빌드·배포 — 19의 우아함을 체험

```bash
# ko가 이미지를 kind에 직접 로드하게 (레지스트리 불필요)
export KO_DOCKER_REPO=kind.local
export KIND_CLUSTER_NAME=tekton-dev

ko apply -f config/ 2>&1 | tail -5      # 소스→이미지→매니페스트 치환→apply 한 방
kubectl -n tekton-pipelines wait --for=condition=ready pod --all --timeout=300s
kubectl -n tekton-pipelines get pods
```

예상: controller·webhook Pod Running — **Dockerfile 없이, 데몬 의존 없이** 소스에서 클러스터까지 한 명령. ✅ 19에서 배운 ko의 실전 사용처가 바로 이 프로젝트입니다(Tekton 자체가 ko로 개발됩니다).

## Step 3. TaskRun 하나로 16 복습 — 사용자 관점 재확인

```bash
kubectl apply -f - <<'EOF'
apiVersion: tekton.dev/v1
kind: TaskRun
metadata: { name: hello-trace }
spec:
  taskSpec:
    steps:
      - name: first
        image: alpine
        script: echo "step 1" && sleep 3
      - name: second
        image: alpine
        script: echo "step 2"
EOF
sleep 30
kubectl get taskrun hello-trace -o jsonpath='{.status.conditions[0].reason}'; echo
kubectl get pod -l tekton.dev/taskRun=hello-trace -o jsonpath='{.items[0].spec.containers[*].name}'; echo
```

예상: `Succeeded`, 컨테이너 이름에 step-first·step-second — **Task 1개 = Pod 1개, 스텝 = 컨테이너**(16)를 눈으로.

## Step 4. 스텝 순차의 비밀 확인 — entrypoint 바꿔치기

```bash
kubectl get pod -l tekton.dev/taskRun=hello-trace \
  -o jsonpath='{.items[0].spec.containers[0].command}' ; echo
```

예상: 컨테이너 command가 내 script가 아니라 `/tekton/bin/entrypoint`류 — Tekton이 **entrypoint를 자기 바이너리로 교체**하고, 그 바이너리가 이전 스텝 완료를 기다렸다 원래 명령을 실행합니다(theory §3). ✅ "컨테이너는 동시에 뜨는데 스텝은 순서대로"의 트릭을 실물로 확인 — 소스는 `cmd/entrypoint/`와 `pkg/pod/`.

## Step 5. reconcile에 내 로그 심기 — 수정→ko apply 루프

```bash
# TaskRun reconcile 진입점 찾기
grep -n "func (c \*Reconciler) ReconcileKind" pkg/reconciler/taskrun/taskrun.go | head -1
```

해당 함수 초입에 식별 로그 한 줄을 추가하세요(예: `logger.Infof("[mine] reconciling taskrun %s", tr.Name)`). 그 후:

```bash
ko apply -f config/ 2>&1 | tail -2      # 재빌드·재배포 — 이것이 전부입니다
kubectl -n tekton-pipelines rollout status deploy/tekton-pipelines-controller --timeout=120s

kubectl create -f - <<'EOF'
apiVersion: tekton.dev/v1
kind: TaskRun
metadata: { generateName: probe- }
spec:
  taskSpec:
    steps: [{ name: s, image: alpine, script: "echo probe" }]
EOF
sleep 15
kubectl -n tekton-pipelines logs deploy/tekton-pipelines-controller --since=2m | grep "\[mine\]" | head -2 \
  && echo "→ 내 코드가 reconcile 경로에서 돌았다 ✅"
git checkout -- pkg/reconciler/taskrun/taskrun.go
```

✅ **수정 → `ko apply` → 확인**: 세 번째 개발 루프 스타일 완성 — 26(로컬 프로세스+_diag), 27(goreman 로컬), 28(ko 재배포). 프로젝트마다 루프가 다르지만 "루프부터 확보"라는 원칙은 같습니다.

## Step 6. 단위 테스트 — Pod 변환 로직은 순수하게 테스트됩니다

```bash
go test ./pkg/reconciler/taskrun/resources/ -run TestPod -count=1 2>&1 | tail -3
```

예상: 통과 — Task→Pod 변환은 클러스터 없이 도는 단위 테스트로 덮여 있습니다(05의 피라미드가 컨트롤러 저장소에서도: 변환 로직은 단위로, 실행 순서는 e2e로). ✅ 기여 시 이 파일들(pod_test.go)이 내 재현 테스트가 들어갈 자리입니다.

## Step 7. 산출물 — 추적 지도

```markdown
# TaskRun의 여정 (오늘 확인한 것)
TaskRun 생성 → reconciler/taskrun.ReconcileKind (Step 5에서 로그 심은 곳)
  → resources/pod.go MakePod (스텝→컨테이너, entrypoint 교체 — Step 4에서 실물 확인)
  → Pod 생성·감시 → 컨테이너 릴레이(완료 파일) → status 갱신 → Succeeded (Step 3)
★ 16의 모든 사용 지식이 이 경로 위의 코드로 매핑됐습니다
```

## 정리

lab-02에서 TEP·catalog로 이어집니다. 클러스터·클론 유지.
