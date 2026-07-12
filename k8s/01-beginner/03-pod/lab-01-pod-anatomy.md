# Lab 01 — Pod 해부: 공유 namespace와 pause 컨테이너

> **목표**: "Pod = namespace 공유 그룹"을 명령으로 직접 검증합니다.
> **환경**: 공유 EKS 클러스터 (`kubectl get nodes`로 연결 확인)

## Step 1. 컨테이너 2개짜리 Pod 생성

```bash
cd manifests/
kubectl apply -f multi-container-pod.yaml
kubectl get pod duo
```

예상 출력:
```
NAME   READY   STATUS    RESTARTS   AGE
duo    2/2     Running   0          10s     ← READY 2/2 = 컨테이너 2개
```

## Step 2. 같은 IP인가요? (NET namespace 공유 검증)

```bash
kubectl exec duo -c writer -- ip addr show eth0 | grep inet
kubectl exec duo -c web    -- ip addr show eth0 | grep inet
```

예상 출력: **완전히 동일한 IP**
```
inet 192.168.x.x/32 ...
inet 192.168.x.x/32 ...
```

```bash
# writer 컨테이너에서 web 컨테이너의 8080 포트를 localhost로 호출
kubectl exec duo -c writer -- wget -qO- localhost:8080/log.txt | tail -3
```

예상 출력 (web이 서빙하는 파일이 localhost로 응답):
```
Mon Jun 10 12:00:01 UTC 2026
Mon Jun 10 12:00:02 UTC 2026
Mon Jun 10 12:00:03 UTC 2026
```

✅ **검증 포인트 2개가 한 번에**: ① 다른 컨테이너의 포트가 localhost입니다 (NET 공유) ② writer가 쓴 파일을 web이 읽습니다 (볼륨 공유).

## Step 3. 하지만 파일시스템은 분리 (MNT namespace)

```bash
kubectl exec duo -c writer -- touch /tmp/only-in-writer
kubectl exec duo -c web    -- ls /tmp/
```

예상 출력: `only-in-writer` 가 **없습니다**. 공유는 명시적으로 마운트한 볼륨(/data)만입니다.

## Step 4. pause 컨테이너 직접 목격

pause는 K8s API에는 안 보이고 **노드의 런타임 레벨**에 존재합니다. 노드에 들어가 확인합니다:

```bash
NODE=$(kubectl get pod duo -o jsonpath='{.spec.nodeName}')
kubectl debug node/$NODE -it --image=public.ecr.aws/docker/library/busybox:stable
```

노드 디버그 셸 안에서:
```sh
# containerd가 실제로 띄운 컨테이너 목록에서 duo 관련 찾기
chroot /host crictl pods --name duo
chroot /host crictl ps --pod $(chroot /host crictl pods --name duo -q)
```

예상 출력:
```
POD ID        ...  NAME   NAMESPACE
1a2b3c...     ...  duo    default
CONTAINER     ...  NAME    POD ID
aaa111...     ...  writer  1a2b3c...
bbb222...     ...  web     1a2b3c...
```

```sh
# pause는 sandbox라서 crictl ps에 안 나옴 — 프로세스로 확인
chroot /host sh -c 'ps -ef | grep -c "/pause"'
exit
```

예상: 노드의 Pod 수만큼 `/pause` 프로세스가 있습니다.

✅ **검증 포인트**: K8s가 숨겨놓은 세 번째 식구를 직접 봤습니다. `crictl`은 노드 레벨 디버깅의 핵심 도구입니다 (모듈 26에서 본격 사용).

## Step 5. 컨테이너 재시작 ≠ Pod IP 변경 검증

```bash
IP_BEFORE=$(kubectl get pod duo -o jsonpath='{.status.podIP}')
# writer의 PID 1을 죽여서 컨테이너 재시작 유발
kubectl exec duo -c writer -- kill 1
sleep 5
kubectl get pod duo
IP_AFTER=$(kubectl get pod duo -o jsonpath='{.status.podIP}')
echo "before=$IP_BEFORE after=$IP_AFTER"
```

예상 출력:
```
NAME   READY   STATUS    RESTARTS      AGE
duo    2/2     Running   1 (5s ago)    10m   ← RESTARTS 1 증가
before=192.168.x.x after=192.168.x.x        ← IP 동일!
```

✅ pause가 namespace를 쥐고 있다는 이론의 실증. RESTARTS 카운트는 올라가도 IP는 불변.

## 트러블슈팅

| 증상 | 원인/해결 |
|------|----------|
| `error: a container name must be specified` | 멀티 컨테이너 Pod는 `-c <이름>` 필수 |
| kubectl debug node가 Pending | 노드 자원 부족 — 다른 노드로: `kubectl debug node/<다른노드>` |
| crictl 권한 에러 | `chroot /host` 를 빼먹었는지 확인 |

## 정리

```bash
kubectl delete pod duo
# (kubectl debug가 만든 디버그 Pod도 정리)
kubectl get pods | grep node-debugger && kubectl delete pod -l app=node-debugger 2>/dev/null || true
```
