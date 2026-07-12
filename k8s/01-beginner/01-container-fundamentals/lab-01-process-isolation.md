# Lab 01 — 컨테이너 = 프로세스임을 직접 확인하기

> **목표**: theory.md의 주장("컨테이너는 격리된 프로세스다")을 명령어로 직접 검증합니다.
> **환경**: 리눅스 셸이 필요합니다. 둘 중 하나를 선택:
> - **A. 로컬**: Docker Desktop (WSL2) — `wsl` 로 들어가서 진행 (무료)
> - **B. AWS**: EC2 t3.small (Amazon Linux 2023) + `sudo dnf install -y docker && sudo systemctl start docker` (~$0.026/h, 실습 후 종료)

---

## Step 1. 컨테이너 하나 띄우기

```bash
docker run -d --name sleeper busybox sleep 3600
```

예상 출력 (컨테이너 ID):
```
f3a91c2e8b...
```

## Step 2. 호스트에서 그 "컨테이너"를 프로세스로 보기

```bash
ps aux | grep "sleep 3600" | grep -v grep
```

예상 출력:
```
root      12345  0.0  0.0   1304   640 ?  Ss  12:00  0:00 sleep 3600
```

✅ **검증 포인트**: 컨테이너 안의 `sleep`이 호스트 프로세스 목록에 **그냥 보입니다**. VM이라면 절대 안 보입니다. 컨테이너 = 호스트의 프로세스라는 증거 1호.

## Step 3. PID namespace 격리 확인 — 같은 프로세스, 다른 번호

```bash
# 컨테이너 안에서 본 자기 자신
docker exec sleeper ps
```

예상 출력:
```
PID   USER     TIME  COMMAND
    1 root      0:00 sleep 3600     ← 안에서는 PID 1
   ...
```

호스트에서는 12345번이던 프로세스가 안에서는 **PID 1**입니다. 같은 프로세스를 두 개의 "시야(namespace)"가 다르게 보여주는 것.

```bash
# 커널이 기록한 namespace ID 직접 보기
HOST_PID=$(docker inspect -f '{{.State.Pid}}' sleeper)
sudo ls -l /proc/$HOST_PID/ns/
```

예상 출력:
```
lrwxrwxrwx ... net -> 'net:[4026532xxx]'
lrwxrwxrwx ... pid -> 'pid:[4026532yyy]'
lrwxrwxrwx ... mnt -> 'mnt:[4026532zzz]'
...
```

```bash
# 비교: 호스트 자신의 namespace
sudo ls -l /proc/self/ns/ | head -5
```

✅ **검증 포인트**: `net:[...]` 숫자가 서로 다릅니다 — 이 숫자가 곧 "어느 칸막이에 있는가"다.

## Step 4. NET namespace — 컨테이너만의 네트워크 세상

```bash
docker exec sleeper ip addr show
```

예상 출력 (호스트와 다른 IP):
```
1: lo: ...
2: eth0@if23: ... inet 172.17.0.2/16 ...
```

호스트의 `ip addr` 결과와 비교해보세요. 인터페이스 구성 자체가 다릅니다.

## Step 5. cgroup — 메모리 제한이 실제로 죽이는지 확인

```bash
# 메모리 50MB 제한 컨테이너에서 일부러 100MB를 셸 변수로 적재
# $(...) 명령 치환이 100MB를 셸(PID 1) 메모리에 담는 순간 한도 초과 → OOM kill
# --memory-swap=50m 으로 스왑 여유를 없애 OOM이 확실히 트리거되게 합니다
docker run --rm --memory=50m --memory-swap=50m --name oom-test busybox \
  sh -c 'A=$(head -c 100000000 /dev/zero | tr "\0" "x")'
echo "exit code: $?"
```

예상 출력:
```
exit code: 137        ← 128 + 9(SIGKILL) = OOM kill
```

> ⚠️ 흔한 실수: `... | tail | sleep 5` 처럼 파이프라인으로 쓰면 `$?`는 **마지막 명령(`sleep`)의 종료 코드**라 137이 아니라 0이 뜹니다. 메모리를 소비하는 프로세스가 PID 1(셸)이 되도록 위처럼 단일 명령으로 구성하고, `--memory-swap`으로 스왑을 차단해야 137이 안정적으로 재현됩니다.

```bash
# 커널 로그에서 OOM 킬 기록 확인 (환경에 따라 dmesg 권한 필요)
sudo dmesg | grep -i "out of memory" | tail -3
```

✅ **검증 포인트**: exit code **137**. K8s에서 Pod 상태에 뜨는 `OOMKilled`가 바로 이 커널 동작입니다. cgroup 파일도 직접 볼 수 있습니다:

```bash
docker run -d --memory=50m --name limited busybox sleep 600
CID=$(docker inspect -f '{{.Id}}' limited)
# cgroup v2 기준 (경로는 배포판에 따라 다를 수 있음)
cat /sys/fs/cgroup/system.slice/docker-$CID.scope/memory.max
```

예상 출력:
```
52428800        ← 50MiB를 바이트로 적어놓은 것이 전부입니다
```

## Step 6. (보너스) Docker 없이 손으로 컨테이너 비슷한 것 만들기

```bash
# unshare = namespace를 새로 만들어 명령 실행하는 표준 도구
sudo unshare --pid --fork --mount-proc sh -c 'echo "내 PID는: $$"; ps'
```

예상 출력:
```
내 PID는: 1
PID TTY  TIME     CMD
  1 ...  00:00:00 sh
  2 ...  00:00:00 ps
```

✅ 방금 도구 없이 PID namespace 격리를 만들었습니다. Docker가 하는 일도 본질적으로 이것(+ 마운트/네트워크/cgroup 설정)입니다.

## 트러블슈팅

| 증상 | 원인/해결 |
|------|----------|
| `permission denied ... docker.sock` | `sudo usermod -aG docker $USER` 후 재로그인 |
| WSL2에서 `cgroup ... memory.max` 없음 | WSL2는 cgroup 경로가 다름 — `find /sys/fs/cgroup -name "memory.max" -path "*docker*"` 로 탐색 |
| EC2에서 docker 명령 없음 | AL2023: `sudo dnf install -y docker && sudo systemctl enable --now docker` |
| Step 5에서 137이 아니라 0 | `--memory-swap` 기본값 때문에 스왑으로 버틴 것 — `--memory=50m --memory-swap=50m` 으로 재시도 |

## 정리

```bash
docker rm -f sleeper limited 2>/dev/null
# EC2를 썼다면 인스턴스 중지/종료 잊지 말 것!
```
