# Lab 01 — 로그 경로 심층: CRI 포맷·로테이션·kubectl logs

> 01의 투어를 심화합니다 — CRI 포맷의 각 필드를 해부하고, 로테이션으로 로그가 실제로 잘려나가는 것을 재현하고(유실의 물리), --previous로 죽은 컨테이너의 유언을 회수합니다.

## 0. 준비

```bash
kind create cluster --name logging
```

## 1. CRI 포맷 해부

```bash
# 다양한 출력을 만드는 Pod: stdout·stderr·긴 줄
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: talker }
spec:
  containers:
    - name: app
      image: busybox
      command: ["sh","-c"]
      args:
        - |
          echo "normal stdout line";
          echo "error line" >&2;
          # 16KB 넘는 긴 줄 (P 플래그 유발)
          head -c 20000 /dev/zero | tr '\0' 'x'; echo;
          sleep 3600
EOF
kubectl wait pod/talker --for=condition=Ready --timeout=60s

# 노드에서 원본 파일 확인
docker exec obs-tour-control-plane true 2>/dev/null || true
docker exec logging-control-plane sh -c \
  'cut -c1-80 /var/log/pods/default_talker_*/app/0.log | head -6'
# 2026-...Z stdout F normal stdout line
# 2026-...Z stderr F error line                    ← 스트림 분리!
# 2026-...Z stdout P xxxxxxxxxxxx...               ← P = 잘린 조각
# 2026-...Z stdout F xxxx...                       ← 마지막 조각은 F
```

**관찰** — ① stderr가 별도 표기됩니다(수집 후 "에러 스트림만 필터" 가능). ② 20KB 줄이 P/F 조각으로 쪼개졌습니다 — **수집기가 재조립하지 않으면 JSON 로그가 깨진 조각으로 저장**됩니다(06의 함정 예고).

## 2. 로테이션 재현 — 유실의 물리

```bash
# 대량 로그를 뿜는 Pod (10Mi 파일을 빠르게 채움)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: flooder }
spec:
  containers:
    - name: app
      image: busybox
      command: ["sh","-c"]
      # 줄당 ~1KB × 초당 ~2000줄 ≈ 2MB/s
      args: ['i=0; line=$(head -c 1000 /dev/zero | tr "\0" "y");
              while true; do i=$((i+1)); echo "$i $line"; done']
EOF
sleep 30

# 노드에서 회전 확인
docker exec logging-control-plane sh -c \
  'ls -lh /var/log/pods/default_flooder_*/app/'
# 0.log        (현재, 10Mi 근처에서 회전)
# 0.log.20260711-120001   (회전된 파일들)
# ... 최대 5개 유지, 그 이상은 삭제됨

# 첫 줄이 이미 사라졌나요?
kubectl logs flooder --tail=1 | awk '{print $1}'   # 현재 카운터 (예: 480000)
kubectl logs flooder | head -1 | awk '{print $1}'  # 남아있는 가장 오래된 줄
# → 1이 아닙니다! 초기 로그는 회전으로 이미 삭제됨
```

**핵심** — 30초 만에 초기 로그가 사라졌습니다. **노드 로그는 임시 버퍼**입니다. 수집기(06)가 이 속도를 못 따라가면 회전에 밀려 영구 유실 — cncf 14의 "유실의 물리"가 여기서 시작됩니다. 대량 로그 앱일수록 수집 지연 = 유실입니다.

```bash
kubectl delete pod flooder --force --grace-period=0
```

## 3. --previous — 죽은 컨테이너의 유언

```bash
# 시작하자마자 단서를 남기고 죽는 앱 (CrashLoop)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: crasher }
spec:
  containers:
    - name: app
      image: busybox
      command: ["sh","-c"]
      args: ['echo "FATAL: cannot connect to db at db.prod:5432 (dns fail)"; exit 1']
EOF
sleep 20
kubectl get pod crasher
# STATUS: CrashLoopBackOff, RESTARTS: 2+

# 현재 컨테이너는 아직 안 떴거나 곧 죽음 — 로그가 안 잡힐 수 있습니다
kubectl logs crasher 2>&1 | head -1
# (타이밍에 따라 비어있거나 에러)

# ★ 직전 컨테이너의 마지막 로그 = 유언
kubectl logs crasher --previous
# FATAL: cannot connect to db at db.prod:5432 (dns fail)   ← 사인(死因)!
```

**정석 동선** — 재시작 조사: `kubectl describe pod`(왜 죽였나: OOMKilled? Error exit?) + `kubectl logs --previous`(죽기 전 무슨 말: 앱의 관점). 이 조합이 CrashLoop 조사의 1순위입니다(01의 이벤트와 함께).

## 4. 멀티 Pod 로그 — 라벨과 prefix

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: multi
  labels: { app: multi }
spec:
  replicas: 3
  selector:
    matchLabels: { app: multi }
  template:
    metadata:
      labels: { app: multi }
    spec:
      containers:
        - name: multi
          image: busybox
          command:
            - sh
            - -c
            - 'while true; do echo "pod says hello at $(date +%T)"; sleep 5; done'
EOF
kubectl wait deploy/multi --for=condition=Available --timeout=60s

# 세 Pod의 로그를 한 번에 + 어느 Pod의 줄인지
kubectl logs -l app=multi --prefix --tail=2
# [pod/multi-xxx/busybox] pod says hello at 12:00:01
# [pod/multi-yyy/busybox] pod says hello at 12:00:03
# [pod/multi-zzz/busybox] pod says hello at 12:00:02
```

**관찰** — `-l`+`--prefix`로 서비스 단위 로그를 즉석에서 봅니다. 하지만 이것도 "지금, 이 클러스터, 남아있는 것"만입니다 — 지난주 로그·죽은 Pod의 로그·여러 클러스터는 중앙 수집(06~)이 필요한 이유입니다.

## 5. 정리

```bash
kubectl delete pod talker crasher --force --grace-period=0 2>/dev/null || true
kubectl delete deploy multi
# 클러스터는 lab-02에서 계속
```

## 정리

- CRI 포맷: 시각·스트림(stdout/err 분리)·플래그 — **P/F 재조립을 모르면 긴 JSON이 깨집니다**(06)
- 로테이션(10Mi×5)은 빠릅니다 — 30초 만에 초기 로그 소멸, **수집 지연 = 유실**
- `--previous` = 죽은 컨테이너의 유언 — describe(왜 죽었나)와 함께 CrashLoop 조사 정석
- `-l`+`--prefix` = 서비스 단위 즉석 로그 — 단, 남아있는 것만 (중앙 수집의 필요)
- **★ 노드 로그는 임시 버퍼입니다 — 보존·검색·집계는 전부 파이프라인(06~)의 몫**
