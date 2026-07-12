# 이론 — kubelet SyncLoop, CRI, QoS와 Eviction

> **🌱 17세 눈높이 비유: 행사장 현장 매니저**
> 본사(API 서버)가 "이 부스(Pod)들을 너네 행사장에 설치해"라고 내려보내면, 현장 매니저(kubelet)는:
> ① 부스 골조(pause/sandbox)부터 세우고 ② 전기 배선(CNI 호출)을 연결하고 ③ 준비 작업자(init)를 순서대로 들이고 ④ 본 작업자(컨테이너)들을 입장시킵니다.
> 설치는 직접 안 합니다 — **시공 업체(containerd)에 표준 발주서(CRI)** 로 시킵니다. 업체가 바뀌어도(CRI-O) 발주서 양식이 같아서 문제없습니다.
> 행사장이 좁아지면(디스크/메모리 압박) 매니저는 **덜 중요한 부스부터 철거**(eviction)합니다 — 철거 순서표가 QoS 클래스입니다.

---

## 1. kubelet SyncLoop — 노드의 심장 박동

```
입력 채널들 ──▶ syncLoop ──▶ Pod 워커들 (Pod마다 고루틴) ──▶ SyncPod()
  ├ API 서버 watch (내 노드 배정 Pod)
  ├ static Pod 파일 디렉터리 (/etc/kubernetes/manifests)
  ├ PLEG (런타임 상태 변화 감지)
  └ 주기 sync (기본 1s 틱, Pod당 ~1m 정기 재동기화)
```

### Pod 생성 타임라인 (SyncPod의 일)

```
1. RunPodSandbox      ← pause 컨테이너 + namespace 생성 (모듈 03!)
   └ CNI ADD 호출     ← Pod IP 부여 (모듈 27 예고)
2. 볼륨 마운트 대기    ← PVC attach/mount (모듈 08)
3. PullImage          ← imagePullPolicy에 따라
4. init 컨테이너 순차 실행 (+ sidecar 기동)
5. CreateContainer + StartContainer (본 컨테이너들)
6. probe 시작, status를 API 서버에 보고
```

`ContainerCreating`에서 멈췄다면 이 타임라인의 1~4 어딘가입니다 — `kubectl describe`의 이벤트와 kubelet 로그가 단계를 알려줍니다.

### PLEG (Pod Lifecycle Event Generator)

런타임의 컨테이너 상태 변화(죽음, 시작)를 감지해 syncLoop에 알리는 부품. 옛날엔 주기 폴링(relist)이라 컨테이너 수천 개 노드에서 "PLEG is not healthy" → 노드 NotReady 사태의 단골이었습니다 — 현재는 **이벤트 기반(Evented PLEG)** 으로 개선. 이 단어가 노드 장애 로그에 보이면 런타임 응답 지연을 의심하세요.

## 2. CRI — 표준 발주서

kubelet → 컨테이너 런타임의 gRPC 인터페이스. 서비스 2개가 전부:

```
RuntimeService:  RunPodSandbox / CreateContainer / StartContainer /
                 StopContainer / ExecSync / PortForward ...
ImageService:    PullImage / ListImages / RemoveImage / ImageFsInfo
```

- 구현체: **containerd**(EKS 표준), CRI-O. 소켓: `/run/containerd/containerd.sock`
- dockershim 제거(1.24)의 의미: Docker 데몬은 CRI를 말하지 않아 중간 번역기(shim)를 K8s가 떠안고 있었던 것을 정리한 것
- **crictl** = 이 gRPC를 치는 CLI — kubelet과 같은 눈높이로 노드를 봅니다

## 3. static Pod — 파일이 곧 Pod

kubelet이 `staticPodPath`(보통 /etc/kubernetes/manifests)의 YAML 파일을 **API 서버 없이** 직접 실행합니다.

- 용도: control plane 부트스트랩의 닭-달걀 해결 — kubeadm 클러스터의 apiserver/etcd 자체가 static Pod입니다! ("API 서버를 띄울 Pod를 API 서버에 등록할 수 없으니까")
- API 서버에는 **mirror Pod**로 비치지만(조회용), 거기서 지워도 부활합니다 — 진실은 파일
- EKS: control plane이 관리형이라 노드에서 쓸 일은 드물지만, kubeadm/기여자 트랙(kind)에서 만납니다

## 4. 자원 관리 — QoS와 Eviction

### QoS 클래스 (requests/limits 조합이 결정)

| 클래스 | 조건 | 압박 시 운명 |
|--------|------|--------------|
| **Guaranteed** | 모든 컨테이너 requests == limits | 최후까지 보호 |
| **Burstable** | requests < limits (일부라도) | 중간 — 초과 사용량 많은 순으로 |
| **BestEffort** | requests/limits 없음 | **1순위 철거** |

### Eviction — kubelet의 자체 방어

노드 자원(메모리, 디스크, inode, PID)이 임계 이하로 떨어지면 kubelet이 **스케줄러/API와 무관하게** Pod를 쫓아냅니다:

```
memory.available < 100Mi (기본 hard 한계) → 즉시 eviction
nodefs.available < 10% → 이미지 GC 먼저, 그래도 부족하면 eviction
```

- 순서: BestEffort → Burstable(초과 사용 큰 순) → Guaranteed(거의 안 건드림)
- **OOMKill과 구분**: OOMKill은 커널이 cgroup 한도 초과 **컨테이너**를 죽이는 것(모듈 01), Eviction은 kubelet이 노드 보호를 위해 **Pod**를 정리하는 것. 메시지도 다릅니다(OOMKilled vs Evicted)
- requests를 정직하게 적는 것이 곧 eviction에서 살아남는 길 — "requests는 보험료"

## 5. 노드 디버깅 루틴 (외울 것)

```bash
kubectl describe node <node>           # 컨디션(MemoryPressure 등), 이벤트
kubectl debug node/<node> -it --image=busybox   # 노드 진입
  chroot /host
  journalctl -u kubelet --since "10 min ago" | tail -50    # kubelet 로그
  crictl pods / crictl ps -a / crictl logs <cid>           # 런타임 눈높이
  crictl inspectp <pod-id>                                  # sandbox 상세 (IP 등)
  systemctl status containerd
```

## 6. 소스코드에서 확인하기

- SyncLoop: `pkg/kubelet/kubelet.go`의 `syncLoop`/`syncLoopIteration` — 입력 채널 select문이 위 그림 그대로
- SyncPod(생성 타임라인): `pkg/kubelet/kuberuntime/kuberuntime_manager.go` — 주석이 단계별로 친절합니다
- CRI 정의: `staging/src/k8s.io/cri-api/pkg/apis/runtime/v1/api.proto`
- eviction: `pkg/kubelet/eviction/eviction_manager.go`

## 요약 카드

| 질문 | 답 |
|------|----|
| Pod 생성의 첫 CRI 호출? | RunPodSandbox (pause + namespace + CNI) |
| crictl의 정체? | kubelet과 동일한 CRI 소켓을 치는 CLI |
| static Pod의 진실 원본? | 노드의 파일 (API의 mirror는 조회용) |
| QoS 3클래스 결정 기준? | requests/limits 조합 |
| Evicted vs OOMKilled? | kubelet의 노드 보호 vs 커널의 cgroup 집행 |
| PLEG 단어가 보이면? | 런타임 응답 지연 → 노드 NotReady 위험 신호 |
