# Lab 01 — 신무기 실습: in-place resize, Job 정밀 제어, schedulingGates

## Step 1. In-place Pod Resize — 재시작 없는 리소스 변경

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: resizable }
spec:
  containers:
  - name: app
    image: registry.k8s.io/e2e-test-images/agnhost:2.53
    command: ["/agnhost", "netexec", "--http-port=8080"]
    resizePolicy:
    - { resourceName: cpu, restartPolicy: NotRequired }      # CPU는 무중단 변경 허용
    - { resourceName: memory, restartPolicy: NotRequired }
    resources:
      requests: { cpu: 100m, memory: 64Mi }
      limits: { cpu: 200m, memory: 128Mi }
EOF
kubectl wait --for=condition=Ready pod/resizable

# 변경 전 기록
kubectl get pod resizable -o jsonpath='restarts={.status.containerStatuses[0].restartCount} cpu={.spec.containers[0].resources.requests.cpu}{"\n"}'

# ★ resize 서브리소스로 라이브 변경
kubectl patch pod resizable --subresource=resize --type=merge -p \
  '{"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"300m","memory":"96Mi"},"limits":{"cpu":"500m","memory":"192Mi"}}}]}}'
sleep 5
kubectl get pod resizable -o jsonpath='restarts={.status.containerStatuses[0].restartCount} cpu={.spec.containers[0].resources.requests.cpu} allocated={.status.containerStatuses[0].allocatedResources.cpu}{"\n"}'
```

예상 출력:
```
restarts=0 cpu=100m
restarts=0 cpu=300m allocated=300m      ← 재시작 0으로 cpu가 바뀌었습니다!
```

✅ **Pod 재시작 없이 cgroup이 갱신**됐습니다. 노드에서 검증하면(모듈 26의 기술) `cpu.max` 파일이 실제로 바뀐 것을 볼 수 있습니다. "리소스 변경 = 재배포"라는 상식이 깨지는 순간 — VPA/rightsizing의 판도를 바꾸는 기능.

> 주의: resize는 Pod 단독 객체 기준 기능입니다. Deployment 산하 Pod를 resize해도 **template은 안 바뀌므로** 다음 롤링 때 원복됩니다 — 영구 변경은 여전히 template 수정.

## Step 2. Job podFailurePolicy — exit code로 운명 분기

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata: { name: smart-retry }
spec:
  backoffLimit: 5
  podFailurePolicy:
    rules:
    - action: FailJob              # 코드 42 = 데이터 자체가 글러먹음 → 재시도 무의미
      onExitCodes: { containerName: worker, operator: In, values: [42] }
    - action: Ignore               # 노드 사정(축출)은 카운트하지 않기
      onPodConditions: [{ type: DisruptionTarget }]
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: worker
        image: public.ecr.aws/docker/library/busybox:stable
        command: ["sh", "-c", "echo 'bad data!'; exit 42"]
EOF
sleep 15
kubectl get job smart-retry -o jsonpath='{.status.conditions[?(@.type=="Failed")].message}'; echo
kubectl get pods -l job-name=smart-retry --no-headers | wc -l
```

예상 출력:
```
Pod default/smart-retry-... has condition DisruptionTarget / matched rule at index 0 (메시지 형식은 버전에 따라 다름)
1        ← 재시도 없이 1번에 끝! (backoffLimit 5가 남았는데도)
```

✅ exit 42 → **즉시 FailJob** — 무의미한 5회 재시도(와 그 시간/비용)를 건너뛰었습니다. 모듈 20의 "멱등성+재시도" 설계에 정밀도가 더해진 것.

## Step 3. schedulingGates — 스케줄링을 의도적으로 보류

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: gated }
spec:
  schedulingGates:
  - name: example.com/budget-approval        # "예산 승인까지 배치 보류"
  containers:
  - { name: c, image: public.ecr.aws/docker/library/busybox:stable, command: [sleep, "300"] }
EOF
kubectl get pod gated
```

예상 출력:
```
NAME    READY   STATUS            RESTARTS   AGE
gated   0/1     SchedulingGated   0          5s     ← Pending도 아닌 전용 상태!
```

```bash
# 외부 시스템(여기선 우리)이 승인 → 게이트 제거
kubectl patch pod gated --type=json -p='[{"op":"remove","path":"/spec/schedulingGates"}]'
kubectl get pod gated -w   # → 즉시 스케줄링 진행 (Ctrl+C)
```

✅ 모듈 25의 PreEnqueue 확장점이 사용자 기능으로 노출된 것. 용도: 배치 큐 시스템(Kueue 등)이 "자원 예약이 승인된 작업만" 스케줄러에 입장시키는 구조.

## Step 4. DisruptionTarget condition — 죽음의 사유서

```bash
# 선점/축출을 당한 Pod에 남는 표준 기록 (모듈 12 선점 실험을 재현했다면):
kubectl get pod <죽은pod> -o jsonpath='{.status.conditions[?(@.type=="DisruptionTarget")]}' 2>/dev/null
# 예: {"type":"DisruptionTarget","status":"True","reason":"PreemptionByScheduler",...}
```

reason 값들: PreemptionByScheduler / EvictionByEvictionAPI / DeletionByTaintManager / TerminationByKubelet — **"누가 왜 죽였나"가 API로 표준화**됐습니다. 사후분석 자동화의 토대.

## 정리

```bash
kubectl delete pod resizable gated --ignore-not-found
kubectl delete job smart-retry --ignore-not-found
```
