# Lab 02 — CKAD/CKS형 모의 7문 (제한 50분)

> 준비: `kubectl create ns exam2`. 규칙은 lab-01과 동일. (CKS형은 모듈 32·33의 복습이기도 합니다)

---

**문제 1 (6분, CKAD).** 멀티컨테이너 Pod `duo`: 컨테이너 `app`(busybox)은 `date >> /shared/log.txt`를 5초마다, 컨테이너 `reader`(busybox)는 `tail -f /shared/log.txt`. emptyDir로 공유. reader 로그에서 날짜가 흐르는지 검증.

**문제 2 (5분, CKAD).** ConfigMap `appcfg`(MODE=prod, TIMEOUT=30)를 만들고, 이를 **환경변수로** 주입받는 Pod `cfg-pod`(busybox, `env` 출력 후 sleep)를 만들어 로그로 검증하세요.

**문제 3 (6분, CKAD).** Job `batch`: busybox로 `echo processing; sleep 2` 를 **총 6회 완료, 동시 2개**로 실행. 완료 후 자동 삭제되도록 TTL 60초 설정. COMPLETIONS 6/6 검증.

**문제 4 (7분, CKAD).** Deployment `api`(nginx:1.27, replicas 2)에 ① liveness(/, port 80, 10초마다) ② readiness(/, port 80, 5초마다) ③ requests cpu=100m/memory=64Mi, limits memory=128Mi 를 추가하세요.

**문제 5 (7분, CKS).** Pod `hardened`(busybox, sleep 3600)를 restricted 기준으로: runAsNonRoot(uid 10001), 모든 capabilities drop, allowPrivilegeEscalation false, seccomp RuntimeDefault, 읽기 전용 루트FS. Running 검증.

**문제 6 (6분, CKS).** ns `exam2`에 PSA `enforce=restricted` 라벨을 붙이고, securityContext 없는 평범한 Pod 생성이 **거부되는지** 확인하세요. (문제 5의 hardened 스펙은 통과해야 함)

**문제 7 (8분, CKS).** ServiceAccount 토큰 자동 마운트를 끈 Pod `no-token`(busybox)을 만들고, 컨테이너 안에 `/var/run/secrets/kubernetes.io` 가 없는지 검증하세요. 이것이 막는 공격 경로를 한 줄로 적어라.

---
---

## 풀이

**1.**
```bash
k apply -n exam2 -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: duo }
spec:
  volumes: [{ name: shared, emptyDir: {} }]
  containers:
  - name: app
    image: public.ecr.aws/docker/library/busybox:stable
    command: [sh, -c, 'while true; do date >> /shared/log.txt; sleep 5; done']
    volumeMounts: [{ name: shared, mountPath: /shared }]
  - name: reader
    image: public.ecr.aws/docker/library/busybox:stable
    command: [sh, -c, 'tail -f /shared/log.txt']
    volumeMounts: [{ name: shared, mountPath: /shared }]
EOF
k logs duo -n exam2 -c reader --tail=3     # 날짜 흐름
```

**2.**
```bash
k create cm appcfg -n exam2 --from-literal=MODE=prod --from-literal=TIMEOUT=30
k run cfg-pod -n exam2 --image=public.ecr.aws/docker/library/busybox:stable \
  --overrides='{"spec":{"containers":[{"name":"cfg-pod","image":"public.ecr.aws/docker/library/busybox:stable","command":["sh","-c","env; sleep 600"],"envFrom":[{"configMapRef":{"name":"appcfg"}}]}]}}'
k logs cfg-pod -n exam2 | grep -E "MODE|TIMEOUT"
```

**3.**
```bash
k create job batch -n exam2 --image=public.ecr.aws/docker/library/busybox:stable \
  $do -- sh -c 'echo processing; sleep 2' > job.yaml
# completions/parallelism/ttl 추가 후 적용 (vim 3줄)
#   spec: { completions: 6, parallelism: 2, ttlSecondsAfterFinished: 60, template: ... }
k apply -f job.yaml; k get job batch -n exam2 -w    # 6/6
```

**4.**
```bash
k create deploy api -n exam2 --image=public.ecr.aws/nginx/nginx:1.27 --replicas=2
k patch deploy api -n exam2 --type=strategic -p '{
 "spec":{"template":{"spec":{"containers":[{"name":"nginx",
  "livenessProbe":{"httpGet":{"path":"/","port":80},"periodSeconds":10},
  "readinessProbe":{"httpGet":{"path":"/","port":80},"periodSeconds":5},
  "resources":{"requests":{"cpu":"100m","memory":"64Mi"},"limits":{"memory":"128Mi"}}}]}}}}'
k get deploy api -n exam2    # 2/2
```

**5.** (모듈 32의 "모범 Pod" 그대로)
```bash
k apply -n exam2 -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: hardened }
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    seccompProfile: { type: RuntimeDefault }
  containers:
  - name: c
    image: public.ecr.aws/docker/library/busybox:stable
    command: [sleep, "3600"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities: { drop: [ALL] }
      readOnlyRootFilesystem: true
EOF
k get pod hardened -n exam2    # Running
```

**6.**
```bash
k label ns exam2 pod-security.kubernetes.io/enforce=restricted
k run plain -n exam2 --image=public.ecr.aws/docker/library/busybox:stable -- sleep 600
# → Error: violates PodSecurity "restricted" (allowPrivilegeEscalation, capabilities, seccomp...)
```
거부 메시지가 **무엇을 고치면 되는지** 그대로 알려줍니다 — 모듈 32.

**7.**
```bash
k apply -n exam2 -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: no-token }
spec:
  automountServiceAccountToken: false
  securityContext: { runAsNonRoot: true, runAsUser: 10001, seccompProfile: { type: RuntimeDefault } }
  containers:
  - name: c
    image: public.ecr.aws/docker/library/busybox:stable
    command: [sleep, "3600"]
    securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: [ALL] } }
EOF
k exec no-token -n exam2 -- ls /var/run/secrets/kubernetes.io 2>&1   # No such file
```
막는 경로: **컨테이너가 장악돼도 SA 토큰으로 API 서버에 접근(권한 상승/정찰)하는 단계를 차단** (모듈 11/32의 ③단계).

## 복기

이 14문제(lab-01+02)가 시험의 전부는 아니지만, **모든 풀이가 이미 배운 모듈의 재실행**이었다는 점이 핵심입니다 — 39개 모듈을 통과한 사람에게 자격증은 공부가 아니라 확인 절차입니다. 진짜 다음 단계는 05-contributor 트랙입니다.

```bash
bash cleanup.sh
```
