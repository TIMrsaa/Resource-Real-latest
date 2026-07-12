# Lab 01 — containerd 아키텍처와 CRI 흐름, shim의 수호 확인

03에서 프로세스 트리로 본 것을 이제 도구로 열어봅니다 — 플러그인, CRI 흐름, 그리고 shim이 컨테이너를 지키는 것.

전제: kind, kubectl, docker.

## Step 1. 클러스터와 노드 진입

```bash
kind create cluster --name ctrd -q
kubectl run demo --image=nginx
kubectl wait --for=condition=ready pod/demo --timeout=120s

# kind 노드가 곧 containerd 호스트
N() { docker exec ctrd-control-plane "$@"; }
```

## Step 2. 플러그인 — 데몬의 구성

```bash
N ctr plugins list 2>/dev/null | grep -E "cri|snapshot|content|runtime" | head -12
echo ""
echo "→ CRI·스냅샷터·콘텐츠·런타임이 전부 플러그인 (theory §1)"
```

✅ containerd가 단일 프로그램이 아니라 **플러그인의 조립**임을 확인.

## Step 3. CRI 뷰(crictl) vs 네이티브 뷰(ctr) — 네임스페이스의 함정

```bash
echo "=== crictl: kubelet과 같은 뷰 (자동 k8s.io) ==="
N crictl ps 2>/dev/null | head -5

echo ""
echo "=== ctr: 네임스페이스 없으면 안 보인다 ==="
N ctr containers list 2>/dev/null | head -3
echo "→ 위가 비었나요? (default 네임스페이스라 K8s 컨테이너가 없습니다)"

echo ""
echo "=== ctr -n k8s.io: K8s 컨테이너가 보인다 ==="
N ctr -n k8s.io containers list 2>/dev/null | head -5
```

✅ **`ctr -n k8s.io`** — theory §6의 함정. 이것을 모르면 "ctr로 봤는데 아무것도 없어요"의 미궁에 빠집니다.

## Step 4. pause 컨테이너 — Pod 네임스페이스의 수호자

```bash
echo "=== Pod마다 있는 pause 컨테이너 ==="
N crictl pods 2>/dev/null | head -4
echo ""
N ctr -n k8s.io containers list 2>/dev/null | grep -i pause | head -3
echo ""
N crictl ps -a 2>/dev/null | grep -i pause | head -2 || \
  echo "(pause는 sandbox라 crictl pods로 보이고, crictl ps에는 앱 컨테이너만)"

cat <<'EOF'
pause 컨테이너 (theory §2):
  RunPodSandbox가 만드는 최소 컨테이너
  → Pod의 네트워크 네임스페이스를 "잡아둔다"
  → 앱 컨테이너가 죽고 재시작해도 Pod IP·네임스페이스 유지
  → "노드에 Pod마다 pause가 있는" 이유
EOF
```

## Step 5. CRI 흐름 관찰 — 새 Pod의 여정

```bash
# containerd 로그를 보며 새 Pod 생성
kubectl run traced --image=busybox --command -- sleep 3600 &
sleep 8

echo "=== containerd 로그에서 CRI 흐름 ==="
N journalctl -u containerd --no-pager -n 200 2>/dev/null | \
  grep -iE "RunPodSandbox|PullImage|CreateContainer|StartContainer" | grep traced | head -6 || \
  N crictl ps 2>/dev/null | grep traced

echo "→ RunPodSandbox(pause+CNI) → PullImage → CreateContainer → StartContainer"
```

## Step 6. shim v2 — 컨테이너를 지키는 자

```bash
echo "=== shim 프로세스 (컨테이너/Pod당 하나) ==="
N sh -c 'ps -ef | grep containerd-shim | grep -v grep | head -4'

echo ""
echo "=== shim의 자식이 실제 컨테이너 프로세스 ==="
SHIM_PID=$(N sh -c 'ps -ef | grep containerd-shim | grep -v grep | head -1 | awk "{print \$2}"')
N sh -c "ps --ppid $SHIM_PID -o pid,comm 2>/dev/null | head -4"
echo "→ runc는 없습니다 (만들고 떠남 — 03). shim이 남아 컨테이너를 지킨다"
```

## Step 7. ★ shim의 수호 — containerd를 재시작해도 컨테이너가 삽니다

```bash
echo "=== 재시작 전: 실행 중 컨테이너 ==="
BEFORE=$(N crictl ps -q 2>/dev/null | wc -l)
echo "컨테이너 수: $BEFORE"
DEMO_ID=$(N crictl ps 2>/dev/null | grep nginx | awk '{print $1}' | head -1)
echo "nginx 컨테이너 ID: $DEMO_ID"

echo ""
echo "=== containerd 재시작 ==="
N systemctl restart containerd 2>/dev/null || N sh -c 'kill -HUP $(pidof containerd)'
sleep 8

echo "=== 재시작 후: 같은 컨테이너가 살아있나요? ==="
AFTER=$(N crictl ps -q 2>/dev/null | wc -l)
echo "컨테이너 수: $AFTER"
N crictl ps 2>/dev/null | grep "$DEMO_ID" && echo "→ ✅ 같은 컨테이너가 살아있습니다! (shim이 지켰습니다)" || \
  echo "→ crictl 재연결 대기 중일 수 있음, 잠시 후 재확인"

# Pod도 여전히 Running
kubectl get pod demo
```

예상: containerd를 재시작했는데 **컨테이너와 Pod가 그대로**. ✅ theory §4의 핵심 — shim이 별도 프로세스라 데몬 재시작에도 워크로드가 생존합니다. "containerd 업그레이드가 무중단인 이유".

## Step 8. 산출물

```markdown
# containerd 구조 카드
- 플러그인 데몬: CRI/콘텐츠/스냅샷/런타임 서비스
- 클라이언트: kubelet·crictl(CRI, 자동 k8s.io) / ctr(네이티브, -n k8s.io 필수)
- CRI 흐름: RunPodSandbox(pause+CNI) → PullImage → CreateContainer → StartContainer
- pause 컨테이너: Pod 네트워크 네임스페이스 유지
- shim v2: 컨테이너 stdio·종료 수호 + containerd 독립 → 재시작에도 생존
- 진단: crictl ps/pods/logs, ctr -n k8s.io containers/snapshots/content
```

## 정리

lab-02에서 이미지·스냅샷·확장을 다룹니다. 유지.
