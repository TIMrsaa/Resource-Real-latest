# Lab 01 — securityContext 손잡이를 하나씩 잠그며 효과 확인

## Step 1. 기본값의 민낯 — 아무 설정 없는 컨테이너

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: naked
  labels: { run: naked }
spec:
  containers:
    - name: naked
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
EOF
kubectl wait --for=condition=Ready pod/naked
kubectl exec naked -- id
kubectl exec naked -- sh -c 'grep CapEff /proc/1/status'
```

예상 출력:
```
uid=0(root) gid=0(root) ...                  ← root로 실행 중!
CapEff: 00000000a80425fb                      ← capability 비트맵 (십수 개 보유)
```

```bash
# 보유 capability 해독 (노드에서 capsh가 있으면): 참고 — a80425fb에는 NET_RAW, CHOWN, SETUID... 포함
kubectl exec naked -- sh -c 'touch /evil-binary && echo "루트FS에 파일 설치 가능"'
```

✅ **기본값 = root + 다수 caps + 쓰기 가능 루트FS** — 공격자에게 후한 출발점입니다.

## Step 2. runAsNonRoot — 마스터키 회수

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: nonroot-fail
  labels: { run: nonroot-fail }
spec:
  securityContext:
    runAsNonRoot: true
  containers:
    - name: nonroot-fail
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
EOF
sleep 5; kubectl get pod nonroot-fail
kubectl describe pod nonroot-fail | grep -i error | head -1
```

예상:
```
nonroot-fail   0/1   CreateContainerConfigError
Error: container has runAsNonRoot and image will run as root
```

✅ busybox 이미지는 기본 root — **kubelet이 기동 자체를 거부**했습니다. 해법은 uid 지정:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: nonroot-ok
  labels: { run: nonroot-ok }
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
  containers:
    - name: nonroot-ok
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
EOF
kubectl wait --for=condition=Ready pod/nonroot-ok
kubectl exec nonroot-ok -- id
```

예상: `uid=10001 gid=0` — 비특권 기동. (실무에선 이미지에 `USER 10001`을 굽는 것이 정석 — 모듈 01 pitfall 5)

## Step 3. capabilities drop — 공구함 비우기

```bash
# NET_RAW의 효과 확인: 기본은 ping(raw socket) 가능
kubectl exec naked -- ping -c1 -W1 8.8.8.8 >/dev/null && echo "ping OK (NET_RAW 보유)"

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: no-caps
  labels: { run: no-caps }
spec:
  containers:
    - name: no-caps
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
      securityContext:
        capabilities:
          drop: ["ALL"]
EOF
kubectl wait --for=condition=Ready pod/no-caps
kubectl exec no-caps -- sh -c 'grep CapEff /proc/1/status'
kubectl exec no-caps -- ping -c1 -W1 8.8.8.8 2>&1 | head -1
```

예상 출력:
```
CapEff: 0000000000000000        ← 공구함이 텅 비었습니다
ping: permission denied          ← raw socket 불가 (앱의 HTTP 통신은 전혀 지장 없음!)
```

✅ **drop ALL을 해도 일반 앱(TCP/UDP 소켓)은 아무 문제 없습니다** — "혹시 몰라서 남겨두는" 관성만 버리면 됩니다.

## Step 4. readOnlyRootFilesystem — 설치 방해

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: ro-fs
  labels: { run: ro-fs }
spec:
  containers:
    - name: ro-fs
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
      securityContext:
        readOnlyRootFilesystem: true
      volumeMounts:
        - name: tmp
          mountPath: /tmp          # 쓰기가 필요한 곳만 emptyDir로 뚫어줌
  volumes:
    - name: tmp
      emptyDir: {}
EOF
kubectl wait --for=condition=Ready pod/ro-fs
kubectl exec ro-fs -- sh -c 'touch /evil 2>&1; touch /tmp/scratch && echo "/tmp만 쓰기 가능"'
```

예상 출력:
```
touch: /evil: Read-only file system     ← 악성코드 설치 경로 차단
/tmp만 쓰기 가능                          ← 정당한 쓰기는 emptyDir로
```

## Step 5. allowPrivilegeEscalation의 의미 확인

```bash
kubectl get pod no-caps -o jsonpath='{.spec.containers[0].securityContext}'; echo
# no_new_privs 플래그 확인 (설정했다면 프로세스에 박힙니다)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: no-esc
  labels: { run: no-esc }
spec:
  containers:
    - name: no-esc
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "600"]
      securityContext:
        allowPrivilegeEscalation: false
EOF
kubectl wait --for=condition=Ready pod/no-esc
kubectl exec no-esc -- sh -c 'grep NoNewPrivs /proc/1/status'
```

예상: `NoNewPrivs: 1` — 이 프로세스와 모든 자손은 **setuid 바이너리로도 권한을 못 올립니다** (sudo/passwd류 상승 경로 차단). 커널 플래그 하나가 전부입니다.

## Step 6. 종합 — 모범 템플릿 만들기 (산출물)

theory §4의 템플릿으로 Pod를 만들어 전부 적용된 상태를 확인하고, **manifests/secure-baseline.yaml로 저장**해두라 — 이후 모든 모듈/실무의 출발점.

```bash
kubectl exec secure-app -- sh -c 'id; grep -E "CapEff|NoNewPrivs|Seccomp:" /proc/1/status'
```

예상:
```
uid=10001 ...
CapEff: 0000000000000000
NoNewPrivs: 1
Seccomp: 2          ← 필터 모드 (RuntimeDefault 적용)
```

## 정리

```bash
kubectl delete pod naked nonroot-fail nonroot-ok no-caps ro-fs no-esc secure-app --ignore-not-found
```
