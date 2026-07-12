# 이론 — Kubernetes Troubleshooting 체계

> **🌱 왜 "체계" 가 필요한가?**
> 장애가 났을 때 감으로 명령어 던지면 → 정보는 많은데 원인을 못 찾음.
> 트러블슈팅의 핵심은 **"같은 순서로 같은 정보를 본다"**.
> 이 모듈의 7개 시나리오는 모두 아래 황금 흐름을 따름.

## 1. 트러블슈팅 황금 흐름

```
1. kubectl get <resource>          ← 상태 (Status / Conditions)
2. kubectl describe <resource>     ← Events + 상세 필드
3. kubectl logs (--previous)       ← 앱 자체의 흔적
4. kubectl exec / port-forward     ← 직접 접근 (위 단계 안 되면)
```

> **🧠 왜 이 순서인가?**
> - get = 1초. 가장 싸고 정보 밀도 높음 (Status/Ready/Restarts 만으로 80% 추측 가능).
> - describe = Events 가 K8s 가 사람에게 남긴 메시지. **여기에 답이 있는 경우가 절반 이상**.
> - logs = 앱 관점. K8s 관점(Events) 으로 좁힌 후 봐야 효율적.
> - exec = 마지막 수단. 살아있는 컨테이너가 있어야 가능.

## 2. Pod 라이프사이클과 상태

```
Pending → ContainerCreating → Running → (Succeeded / Failed)
                                  ↓
                              CrashLoopBackOff (재시작 반복)
```

| Status | 의미 | 1순위 점검 |
|--------|------|-----------|
| `Pending` | 스케줄링/이미지 다운로드 전 | `describe` 의 Events |
| `ContainerCreating` | 노드 배정됨, 이미지/볼륨 준비 중 | image pull, PVC, ConfigMap |
| `Running` (Ready=0) | 시작했으나 readinessProbe 실패 | `logs`, probe 설정 |
| `CrashLoopBackOff` | 시작 직후 죽고 재시작 반복 | `logs --previous` + Exit Code |
| `Error` / `Failed` | 종료됨 (RestartPolicy=Never/OnFailure) | `logs --previous` |
| `OOMKilled` | 메모리 limit 초과로 강제 종료 | `Last State`, limits.memory |
| `ImagePullBackOff` | 이미지 못 가져옴 | Events 의 정확한 메시지 |
| `Unknown` | 노드 NotReady → Pod 상태 모름 | 노드 자체 점검 |

> **🧠 Status 만으로 50% 진단**
> Status 는 K8s 가 이미 분류해준 결과. "왜 그 Status 인지" 만 파면 된다.
> 예: `ImagePullBackOff` → 이미지 이름/권한/네트워크 셋 중 하나. Events 에 정답.

## 3. 종료 코드 (Exit Code) 의미

리눅스 표준: `0` 성공 / `1~125` 앱 에러 / `128 + N` = 시그널 N 으로 종료.

| Exit Code | 의미 | 흔한 원인 |
|-----------|------|-----------|
| 0 | 정상 종료 | 의도된 종료인데 RestartPolicy=Always → CrashLoop 처럼 보임 |
| 1 | 앱 에러 | 가장 흔함. 로그 봐야 |
| 126 | 실행 권한 없음 | entrypoint chmod +x 누락 |
| 127 | 명령 못 찾음 | image 의 ENTRYPOINT 오타 |
| 137 | SIGKILL (128+9) | OOMKilled 또는 강제 종료 |
| 139 | SIGSEGV (128+11) | nil pointer, 메모리 위반 |
| 143 | SIGTERM (128+15) | graceful shutdown 무시 → 30초 후 SIGKILL |

> **🧠 137 만 봐도 OOM 의심**
> Exit Code 137 + Reason=OOMKilled = 컨테이너 limit 초과 (가장 흔함).
> Exit Code 137 + Reason=Error = 노드 OOM Killer 가 외부에서 죽임.

## 4. 노드 Conditions

```bash
kubectl describe node <name> | grep -A10 Conditions
```

| Condition | True 의미 | 영향 |
|-----------|----------|------|
| `Ready` | kubelet heartbeat OK | False = NotReady, 5분 후 Pod evict |
| `MemoryPressure` | 메모리 부족 | Pod eviction trigger |
| `DiskPressure` | 디스크 가득 | image GC, Pod eviction |
| `PIDPressure` | PID 고갈 | 신규 프로세스 fork 실패 |
| `NetworkUnavailable` | 라우팅 안 됨 | CNI Pod 점검 |

> **🧠 Conditions 가 NotReady 의 1차 단서**
> Ready=False 일 때 다른 Condition 도 같이 봐야 원인을 좁힘.
> 예: Ready=False + DiskPressure=True → 디스크 정리.

## 5. Service 호출 경로 (디버깅 흐름)

```
Client Pod
   ↓ DNS 해석 (CoreDNS)
   ↓ ClusterIP (가상 IP)
   ↓ kube-proxy iptables / IPVS
   ↓ Endpoints (실제 Pod IP 목록)
   ↓ Pod
```

각 단계별 진단 명령:

| 단계 | 명령 | 정상 신호 |
|------|------|-----------|
| DNS | `nslookup <svc>` (디버그 Pod 안에서) | ClusterIP 반환 |
| Service | `kubectl get svc <name>` | ClusterIP 존재 |
| Endpoints | `kubectl get endpoints <name>` | Pod IP 목록 채워짐 |
| Pod | `kubectl exec <pod> -- curl localhost:<port>` | 200 OK |

> **🧠 Endpoints 비어있으면 selector 부터**
> Endpoints 객체는 "Service.spec.selector 와 매칭 + Ready=True" 인 Pod IP 만 채움.
> 비어있다 = selector 오타 또는 Pod 가 Ready 가 아님.

## 6. PVC 바인딩 흐름

```
PVC 생성 → StorageClass 확인 → CSI Driver 가 PV 생성 → PVC ↔ PV 바인딩 → Pod 마운트
```

| 멈춘 단계 | 증상 | 원인 |
|-----------|------|------|
| StorageClass | PVC Pending, Events 에 `not found` | StorageClass 오타 |
| CSI Driver | PVC Pending, 진행 안 됨 | IRSA 권한, CSI Pod 죽음 |
| AZ 매칭 | Pod Pending, `volume node affinity conflict` | PV 는 a-AZ, Pod 은 c-AZ |
| WaitForFirstConsumer | PVC Pending, Pod 도 Pending | Pod 가 스케줄돼야 PV 생성 — Pod 부터 |

> **🧠 `WaitForFirstConsumer` 의 chicken-and-egg**
> 이 모드는 "Pod 가 어떤 노드에 갈지 결정될 때 그 AZ 에 PV 만든다".
> 그래서 Pod 가 다른 이유 (resource, taint) 로 Pending 이면 PVC 도 영원히 Pending.
> = PVC 가 아니라 **Pod 의 Pending 원인** 을 먼저 풀어야.

## 7. Events 가 진단의 80%

```bash
# 객체 별
kubectl describe pod <name> | tail -20

# NS 전체, 시간순
kubectl get events --sort-by='.lastTimestamp' | tail -20

# 최근만 (1.30+)
kubectl events --for pod/<name>
```

> **🧠 Events 는 K8s 가 사람에게 보낸 편지**
> Controller / Scheduler / kubelet 이 "내가 이걸 시도했는데 이래서 실패했다" 를 기록.
> 거의 모든 시나리오에서 정답 메시지가 여기 있음.
>
> **함정**: Events 는 기본 1시간 후 사라짐. 장애 직후 캡처 필수.

## 8. 진단 도구 cheatsheet

| 도구 | 용도 | 예 |
|------|------|------|
| `kubectl describe` | Events + 상세 필드 | 1순위 |
| `kubectl logs --previous` | 죽기 전 컨테이너 로그 | CrashLoop 핵심 |
| `kubectl get events` | NS 전체 events | `--sort-by='.lastTimestamp'` |
| `kubectl exec -it` | 컨테이너 안 진입 | 살아있어야 가능 |
| `kubectl port-forward` | 로컬 → Pod 직접 | Service 우회 디버깅 |
| `kubectl debug` | 임시 사이드카 주입 | 디스트로리스 이미지에 유용 |
| `stern` | 다중 Pod 로그 동시 | `stern <prefix>` |
| `k9s` | TUI | 한 화면에서 다수 보기 |

## 9. 결정 트리 — "어디부터 봐야?"

```
증상이 무엇?
├─ Pod 가 Running 이 아님
│  ├─ Pending          → 시나리오 3 (스케줄링)
│  ├─ ContainerCreating → image pull / PVC
│  ├─ ImagePullBackOff → 시나리오 2
│  └─ CrashLoopBackOff → 시나리오 1 (logs --previous)
│
├─ Pod 가 Running 인데 트래픽 못 받음
│  ├─ Ready 0/1        → readinessProbe / 앱 시작 지연
│  └─ Service 무응답   → 시나리오 5 (Endpoints 부터)
│
├─ Pod 가 죽었다 살아남
│  └─ OOMKilled?       → 시나리오 4 (limits 점검)
│
├─ 노드 자체 문제
│  └─ NotReady         → 시나리오 6 (Conditions)
│
└─ 스토리지
   └─ PVC Pending     → 시나리오 7
```

## 10. 운영에서의 원칙

1. **재현 가능한 절차로** — 같은 명령을 같은 순서로 (이 모듈의 시나리오 구조).
2. **Events 부터** — 추측 전에 K8s 가 남긴 메시지부터 읽기.
3. **하나씩 변경** — 동시에 여러 가설 검증 X. 한 번에 한 변수.
4. **로그 보존** — 장애 직후 `kubectl describe`, events, logs 를 파일로 캡처.
5. **post-mortem** — 해결 후 "왜 그랬는지 + 어떻게 막을지" 문서화.

다음: [scenario-1-crashloop.md](./scenario-1-crashloop.md)
