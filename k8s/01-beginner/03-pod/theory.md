# 이론 — Pod: namespace를 공유하는 컨테이너 그룹

> **🌱 17세 눈높이 비유: Pod는 "2인실 기숙사 방"입니다**
> 컨테이너 1명 1명에게 방을 따로 주는 대신, 꼭 붙어 지내야 하는 룸메이트들에게 **방 하나(Pod)** 를 줍니다.
> 같은 방이니: 주소(IP)가 하나, 방 번호로 서로 부를 필요 없이 바로 대화(localhost), 옷장(볼륨) 공유.
> 이사(스케줄링)도 방 단위로 갑니다 — 룸메이트를 찢어서 다른 건물에 보내지 않습니다.

---

## 1. 정의: Pod = 격리 환경을 공유하는 컨테이너 집합

모듈 01에서 컨테이너 = namespace로 격리된 프로세스라고 했습니다. Pod는 그 격리 벽의 일부를 **의도적으로 허문 그룹**입니다.

| namespace | Pod 내 공유 여부 |
|-----------|-----------------|
| NET (IP/포트) | ✅ 공유 — 그래서 서로 localhost, 포트 충돌 주의 |
| IPC | ✅ 공유 |
| UTS (hostname) | ✅ 공유 — hostname = Pod 이름 |
| PID | ❌ 기본 분리 (`shareProcessNamespace: true`로 공유 가능) |
| MNT (파일시스템) | ❌ 분리 — 단, **볼륨**을 통해 특정 디렉터리만 공유 |

## 2. pause 컨테이너 — Pod의 숨겨진 뼈대

`kubectl get pods`에는 안 보이지만, 모든 Pod에는 **pause(infra) 컨테이너**가 하나 더 있습니다.

```
Pod 생성 시 kubelet이 실제로 하는 일:
1. pause 컨테이너 생성  ← namespace 세트를 만들어 "들고" 있는 역할. 하는 일: 영원히 잠자기
2. CNI 호출            ← pause의 NET namespace에 IP 부여
3. 사용자 컨테이너들 생성 ← pause의 namespace에 "참여(join)"시킴
```

**왜 필요한가?** namespace는 그것을 쓰는 프로세스가 다 죽으면 사라집니다. 앱 컨테이너가 namespace 주인이라면, 앱이 재시작될 때 IP도 날아갑니다. 그래서 **절대 안 죽는 최소 프로세스(pause)에게 namespace 소유권**을 주고, 앱 컨테이너들은 세입자로 들어갑니다.

> **🌱 비유**: 기숙사 방의 "명의자"다. 룸메이트(앱)가 잠깐 나갔다 와도(재시작) 방 계약(IP)은 명의자(pause) 앞으로 유지됩니다.
> **💡 효과**: 컨테이너가 크래시로 100번 재시작해도 Pod IP는 그대로입니다.

## 3. 컨테이너의 3가지 종류 (v1.36 기준)

```yaml
spec:
  initContainers:
  - name: wait-for-db          # ① init: 본 컨테이너 전에 순서대로 실행되고 종료
    image: busybox
    command: ["sh", "-c", "until nc -z db 5432; do sleep 1; done"]
  - name: log-agent            # ② 네이티브 sidecar: init 자리에 쓰되 restartPolicy로 구분
    image: fluent-bit
    restartPolicy: Always      #    ← 이 한 줄이 sidecar 선언 (계속 살아있음)
  containers:
  - name: app                  # ③ 본 컨테이너
    image: myapp
```

| 종류 | 실행 시점 | 종료 | 용도 |
|------|----------|------|------|
| init | 본 컨테이너 **전에, 선언 순서대로 하나씩** | 완료되어야 다음 진행 | 대기/사전 설정/권한 준비 |
| sidecar (init + `restartPolicy: Always`) | init 순서에 시작, **본 컨테이너보다 먼저 떠서 나중에 죽음** | Pod 종료까지 | 로그 수집, 프록시, 메시 |
| 일반 | init 완료 후 동시에 | 앱 수명 | 주 애플리케이션 |

> **💡 역사**: 네이티브 sidecar 이전에는 sidecar를 일반 컨테이너로 넣었는데, "Job이 끝났는데 sidecar 때문에 Pod가 안 끝남", "앱보다 sidecar(프록시)가 늦게 떠서 초기 요청 실패" 같은 고질병이 있었습니다. 1.29~1.33에 걸쳐 해결된 것이 이 문법입니다. 옛 자료와 구분할 것.

## 4. 멀티 컨테이너 패턴 3종

| 패턴 | 구조 | 예시 |
|------|------|------|
| **Sidecar** | 앱 + 보조 기능 | 앱 + 로그 수집기(fluent-bit), 앱 + 서비스메시 프록시(envoy) |
| **Ambassador** | 앱 + 외부 통신 대리인 | 앱은 localhost:6379로만 → 앰배서더가 실제 Redis 클러스터로 라우팅 |
| **Adapter** | 앱 + 출력 변환기 | 레거시 앱의 로그 → 표준 포맷으로 변환해 노출 |

공통 원리: **NET/볼륨 공유** 덕분에 앱 코드를 안 고치고 기능을 "옆에 붙인다".

## 5. 라이프사이클

### 5.1 Phase (큰 단계)

```
Pending ──→ Running ──→ Succeeded (모든 컨테이너 정상 종료; Job류)
   │            └─────→ Failed    (어떤 컨테이너가 실패 종료)
   └ (스케줄링/이미지풀 전 단계)        Unknown (노드 연락 두절)
```

phase는 거칩니다. 실제 디버깅은 **conditions**(PodScheduled/Initialized/ContainersReady/Ready)와 **컨테이너 상태**(Waiting/Running/Terminated + reason)를 봅니다. `CrashLoopBackOff`는 phase가 아니라 Waiting의 reason입니다.

### 5.2 restartPolicy

| 값 | 의미 | 용도 |
|----|------|------|
| Always (기본) | 종료 코드 무관 재시작 | 서버 (Deployment) |
| OnFailure | 실패 시만 재시작 | 배치 (Job) |
| Never | 재시작 안 함 | 일회성 |

재시작 간격은 10s→20s→40s... 최대 5분의 **지수 백오프** — `CrashLoopBackOff`의 "BackOff"가 이것입니다.

### 5.3 종료 시퀀스 (외워둘 가치 있음)

```
kubectl delete pod (또는 축출)
  1. Pod가 Terminating 마킹 + EndpointSlice에서 제거 시작 (트래픽 차단)
  2. preStop hook 실행 (있다면)
  3. 컨테이너 PID 1에 SIGTERM
  4. terminationGracePeriodSeconds (기본 30초) 대기
  5. 그래도 안 죽으면 SIGKILL
```

앱이 SIGTERM을 무시하면 30초 후 강제 종료 — 처리 중이던 요청이 끊깁니다. (모듈 14에서 graceful shutdown 구현)

## 6. Pod를 직접 만들지 않는 이유

`kind: Pod`로 만든 Pod는 **컨트롤러가 없습니다**:
- 노드가 죽으면 → 그냥 사라짐 (재생성 없음)
- 업데이트 → 불가 (이미지 바꾸려면 삭제 후 재생성)

Pod는 "소모품 단위"이고, 그 소모품을 관리하는 상위 컨트롤러(Deployment 등 — 다음 모듈)를 쓰는 것이 표준입니다. 이 모듈에서만 학습 목적으로 직접 만듭니다.

## 7. 소스코드에서 확인하기

- pause 컨테이너 소스 (몇 십 줄짜리 C 코드!): https://github.com/kubernetes/kubernetes/blob/master/build/pause/linux/pause.c — "시그널 기다리며 영원히 잠들기"가 전부입니다
- kubelet이 Pod를 시작시키는 함수: `pkg/kubelet/kuberuntime/kuberuntime_manager.go` 의 `SyncPod` — ① pause(sandbox) 생성 ② init 순차 실행 ③ 본 컨테이너 실행이 코드 주석에 그대로 있습니다

## 요약 카드

| 질문 | 답 |
|------|----|
| Pod란? | NET/IPC/UTS namespace와 볼륨을 공유하는 컨테이너 그룹 |
| pause 컨테이너는? | namespace 소유권을 들고 있는 불사신 뼈대 |
| 컨테이너 재시작 시 Pod IP는? | 유지 (pause가 namespace를 쥐고 있으므로) |
| sidecar 선언법(1.36)? | initContainers + `restartPolicy: Always` |
| 종료 시 시그널 순서? | SIGTERM → 유예(기본 30s) → SIGKILL |
