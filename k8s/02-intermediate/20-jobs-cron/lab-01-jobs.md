# Lab 01 — Job: 재시도, 병렬, Indexed

## Step 1. 성공하는 Job — Completed는 정상입니다

```bash
kubectl create job pi --image=public.ecr.aws/docker/library/busybox:stable -- \
  sh -c 'echo "working..."; sleep 5; echo "done"; exit 0'
kubectl get job,pods -l job-name=pi -w
```

예상 (수 초 후, Ctrl+C):
```
job.batch/pi   Complete   1/1
pod/pi-xxxxx   0/1   Completed       ← "죽은 게" 아니라 "성공한 것"
```

```bash
kubectl logs job/pi      # Job 이름으로 로그 조회 가능
```

## Step 2. 실패와 재시도 — backoffLimit

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata: { name: flaky }
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: flaky
        image: public.ecr.aws/docker/library/busybox:stable
        command: ["sh", "-c", "echo attempt at $(date); exit 1"]
EOF
kubectl get pods -l job-name=flaky -w
```

예상: Error Pod가 **점점 긴 간격으로 4개**(최초+재시도 3) 생기고 끝:

```bash
kubectl get job flaky -o jsonpath='{.status.conditions[0].type}: {.status.conditions[0].message}{"\n"}'
```

예상 출력:
```
Failed: Job has reached the specified backoff limit
```

✅ restartPolicy: Never라 실패 Pod들이 **전부 남아 있습니다** — 시도별 로그 부검 가능 (`kubectl logs <각 pod>`). OnFailure였다면 Pod 1개에서 재시작하며 로그가 덮였을 것.

## Step 3. 병렬 — completions / parallelism

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata: { name: crowd-work }
spec:
  completions: 6
  parallelism: 3
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: w
        image: public.ecr.aws/docker/library/busybox:stable
        command: ["sh", "-c", "echo $(hostname) processing; sleep 10"]
EOF
kubectl get pods -l job-name=crowd-work -w
```

예상: **동시에 3개씩**, 끝나는 대로 다음이 떠서 총 6개 Completed. Job은 `6/6 Complete`.

## Step 4. Indexed Job — 자기 몫만 처리하기

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata: { name: sharded }
spec:
  completions: 4
  parallelism: 4
  completionMode: Indexed
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: shard
        image: public.ecr.aws/docker/library/busybox:stable
        command: ["sh", "-c",
          "echo \"shard $JOB_COMPLETION_INDEX: processing rows $((JOB_COMPLETION_INDEX*250))-$(((JOB_COMPLETION_INDEX+1)*250-1))\"; sleep 3"]
EOF
sleep 15
for p in $(kubectl get pods -l job-name=sharded -o name); do kubectl logs $p; done
```

예상 출력:
```
shard 0: processing rows 0-249
shard 1: processing rows 250-499
shard 2: processing rows 500-749
shard 3: processing rows 750-999
```

✅ "1000행을 4등분" — 코디네이터 없이 인덱스만으로 분할 정복. 어느 샤드가 실패하면 **그 인덱스만** 재시도됩니다.

## Step 5. ttl 청소 확인

```bash
kubectl get jobs    # 5분 뒤 crowd-work, sharded가 스스로 사라지는지 (ttl 300)
```

## 정리

```bash
kubectl delete job pi flaky --ignore-not-found   # ttl 없는 것들 수동 정리
```
