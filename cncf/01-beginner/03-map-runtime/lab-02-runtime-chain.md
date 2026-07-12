# Lab 02 — 체인 해부: kubelet→containerd→shim→runc를 눈으로

kind 노드(그 자체가 컨테이너)에 들어가 런타임 체인의 실물 — 프로세스 트리, shim, OCI 번들(config.json) — 을 확인합니다.

전제: kind, kubectl, docker.

## Step 1. 클러스터와 관찰 대상 Pod

```bash
kind create cluster --name runtime -q
kubectl run probe --image=nginx --restart=Never
kubectl wait --for=condition=ready pod/probe --timeout=120s
```

## Step 2. 노드 안으로 — 체인의 현장

```bash
# kind 노드는 도커 컨테이너입니다 — 그 안이 "노드"
docker exec -it runtime-control-plane bash -c '
echo "=== ① kubelet과 containerd (상주 데몬) ==="
ps -eo pid,ppid,comm,args --sort=pid | grep -E "kubelet|containerd( |$)" | grep -v grep | head -4

echo ""
echo "=== ② shim들 — 컨테이너마다 하나씩 상주 ==="
ps -eo pid,ppid,comm | grep containerd-shim | head -6

echo ""
echo "=== ③ 실제 컨테이너 프로세스 — shim의 자식 ==="
SHIM=$(ps -eo pid,comm | grep containerd-shim | head -1 | awk "{print \$1}")
ps --ppid $SHIM -o pid,comm 2>/dev/null | head -5
'
```

예상: kubelet·containerd가 데몬으로, **containerd-shim-runc-v2가 컨테이너 수만큼**, 그 자식으로 nginx·pause 프로세스. ✅ theory §1의 그림이 프로세스 트리 그대로입니다 — 그리고 **runc는 목록에 없습니다**(만들고 떠났습니다 — shim만 남는 이유).

## Step 3. runc의 흔적 — 만들고 떠난 요리사

```bash
docker exec -it runtime-control-plane bash -c '
echo "=== runc 바이너리는 있습니다 (호출될 뿐 상주 안 함) ==="
which runc && runc --version | head -2

echo ""
echo "=== containerd가 runc를 어떻게 아는가 — 설정의 핸들러 ==="
grep -A3 "runtimes.runc" /etc/containerd/config.toml | head -6
echo "→ RuntimeClass의 handler가 가리키는 것이 이 설정 항목 — gVisor를 깔면 runtimes.runsc가 추가된다"
'
```

✅ **RuntimeClass → containerd 설정의 핸들러 → OCI 런타임 바이너리**의 연결 고리 확인 — 격리 스펙트럼의 교체가 "설정 한 블록"임을 눈으로.

## Step 4. OCI 번들 — 명세의 실물 config.json

```bash
docker exec -it runtime-control-plane bash -c '
echo "=== 실행 중 컨테이너의 OCI 번들 위치 ==="
CID=$(crictl ps --name probe -q 2>/dev/null | head -1)
[ -z "$CID" ] && CID=$(crictl ps -q | head -1)
BUNDLE=$(find /run/containerd -name config.json -path "*$CID*" 2>/dev/null | head -1)
[ -z "$BUNDLE" ] && BUNDLE=$(find /run/containerd -name config.json 2>/dev/null | head -1)
echo "$BUNDLE"

echo ""
echo "=== config.json — runtime-spec의 실물 (발췌) ==="
python3 -c "
import json
c = json.load(open(\"$BUNDLE\"))
print(\"process.args:\", c[\"process\"][\"args\"][:3])
print(\"namespaces  :\", [n[\"type\"] for n in c[\"linux\"][\"namespaces\"]])
print(\"cgroupsPath :\", c[\"linux\"].get(\"cgroupsPath\",\"\")[:60])
" 2>/dev/null || head -30 "$BUNDLE"
'
```

예상: process.args(컨테이너의 실행 명령), namespaces 목록(pid·net·mnt... — k8s 초급의 그 개념들), cgroupsPath. ✅ **OCI runtime-spec은 추상이 아니라 이 JSON 파일입니다** — runc든 runsc든 kata든 이 형식을 받아 각자의 방식으로 격리를 만듭니다(교체 가능성의 헌법, theory §2).

## Step 5. CRI로 직접 대화 — kubelet의 언어

```bash
docker exec -it runtime-control-plane bash -c '
crictl version | head -3
echo "---"
crictl pods --name probe
crictl ps --name probe
echo "→ crictl은 CRI(gRPC)로 containerd와 직접 대화 — kubelet이 쓰는 그 인터페이스"
echo "   런타임 층 트러블슈팅의 도구: kubectl(API 서버 경유)이 아니라 crictl(노드 직접)"
'
```

✅ 노드 수준 진단의 도구 체인 완성: **kubectl(제어면) / crictl(CRI) / ctr(containerd 네이티브) / ps·cgroup(커널)** — 층마다 도구가 있습니다.

## Step 6. 산출물 — 체인 카드

```markdown
# 런타임 체인 (오늘 눈으로 본 것)
kubelet ──CRI(gRPC)──▶ containerd ──▶ shim(컨테이너당 1, 상주) ──▶ [runc 호출·종료] ──▶ 프로세스
- runc가 ps에 없는 이유: 만들고 떠남 — stdio·종료는 shim이 지킴
- RuntimeClass = containerd config.toml의 handler 항목 선택
- OCI 번들 = config.json (namespaces·cgroup·args) — 런타임 교체 가능성의 실체
- 진단 도구 층: kubectl / crictl / ctr / ps·/sys/fs/cgroup
```

## 정리

```bash
bash cleanup.sh
```
