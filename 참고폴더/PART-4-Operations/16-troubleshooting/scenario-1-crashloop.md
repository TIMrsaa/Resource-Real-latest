# 시나리오 1 — CrashLoopBackOff

> **🌱 CrashLoopBackOff 가 뭐고 왜 BackOff?**
> Pod의 컨테이너가 시작 후 즉시 죽으면 kubelet이 재시작.
> 또 죽으면 또 재시작... → 무한 루프 방지를 위해 **재시작 간격을 점점 늘림** (10s → 20s → 40s → 최대 5분).
> 이게 "BackOff" (=후퇴) 의 의미.
>
> 영향: Pod 영원히 Ready 안 됨 (=Service에 등록 안 됨, 트래픽 못 받음).

## 1. 재현

```bash
kubectl run crashy --image=busybox --restart=Always -- sh -c "echo starting; exit 1"
sleep 30
```

> **`--restart=Always`**: Pod의 RestartPolicy. Always(기본) / OnFailure / Never.
> Always = 어떤 종료든 재시작. CrashLoop은 Always일 때만 발생.
> Never면 한 번 죽고 끝 (Failed 상태).

## 2. 증상

```bash
kubectl get pod crashy
```

```
NAME     READY   STATUS              RESTARTS   AGE
crashy   0/1     CrashLoopBackOff    3          1m
```

> **각 컬럼 의미**
> - `READY: 0/1` = 1개 컨테이너 중 0개 Ready (= 트래픽 못 받음)
> - `STATUS: CrashLoopBackOff` = 재시작 대기 중
> - `RESTARTS: 3` = 지금까지 3번 재시작 (이 숫자가 계속 늘면 CrashLoop 의심)

## 3. 진단 절차

> **🧠 트러블슈팅 황금 흐름**
> ```
>   1. kubectl get pod        ← 상태 확인 (CrashLoop? Pending? Running?)
>   2. kubectl describe pod   ← Events + Last State 확인
>   3. kubectl logs --previous ← 죽기 전 로그 (CrashLoop 핵심!)
>   4. kubectl exec (안 되면) → init container, volume mount 점검
> ```

### 3.1 마지막 종료 코드

```bash
kubectl describe pod crashy | grep -A3 'Last State\|State:\|Exit Code\|Reason'
```

기대:
```
State:          Waiting
  Reason:       CrashLoopBackOff
Last State:     Terminated
  Reason:       Error
  Exit Code:    1
```

> **🧠 `Last State` vs `State` 차이**
> - **State**: 현재 컨테이너 상태 (Waiting/Running/Terminated)
> - **Last State**: **직전 종료된 컨테이너** 의 상태
>
> CrashLoopBackOff면 현재는 Waiting (재시작 대기), Last State에 종료 정보 있음 = 여기가 핵심!

### 3.2 직전 컨테이너 로그

```bash
kubectl logs crashy --previous
```

기대: `starting` (의도된 출력 + 즉시 종료).

> **🧠 `--previous` 가 핵심**
> 일반 `kubectl logs` = **현재** 컨테이너의 로그.
> CrashLoop 상태에선 현재 컨테이너가 아직 시작 안 했거나 BackOff 대기 중 → 로그 없음.
> `--previous` = **직전에 죽은** 컨테이너의 로그 (kubelet이 보존).
>
> CrashLoop 디버깅의 90%는 `--previous` 로 해결.

### 3.3 Events

```bash
kubectl get events --sort-by='.lastTimestamp' | tail -10
```

`Back-off restarting failed container` 가 보임.

> **`--sort-by='.lastTimestamp'`**: 시간순 정렬. K8s events는 기본 정렬이 무작위라 이게 거의 필수.

## 4. 원인 매핑

| Exit Code | 흔한 원인 |
|-----------|-----------|
| 0 | 정상 종료지만 livenessProbe 가 실패로 간주? |
| 1 | 앱 자체 에러 (가장 흔함) |
| 137 | OOMKilled (또는 SIGKILL 받음) |
| 139 | Segmentation fault |
| 143 | SIGTERM (정상 종료 신호 무시) |

이 경우 1 → 앱 자체 에러. 로그가 단서.

> **🧠 Exit Code 의미를 깊이 이해**
> Linux 표준: 종료 코드 = 0 (성공) / 1~125 (앱 에러) / 126~127 (실행 권한/명령 못 찾음) / 128+N (시그널 N으로 종료).
>
> - **137 = 128 + 9 (SIGKILL)**: OOM Killer 또는 강제 kill. cgroup 메모리 한도 초과 시 일반적
> - **143 = 128 + 15 (SIGTERM)**: K8s가 graceful shutdown 시도했는데 앱이 SIGTERM 무시 → 30초 후 SIGKILL
> - **139 = 128 + 11 (SIGSEGV)**: 메모리 접근 위반. C/C++/Go 앱의 nil pointer 등
>
> Exit Code 만으로 원인 80% 추정 가능.

## 5. 해결

```bash
# 의도된 시나리오라 그냥 정리
kubectl delete pod crashy
```

실제 운영에선:
- 앱 로그 분석 후 코드 수정
- 환경변수/ConfigMap 누락 점검
- liveness/readiness 설정 검증

> **🧠 흔한 CrashLoop 원인 5가지**
> 1. **앱 자체 버그** (예외 처리 실패 → panic) — `--previous` 로그로 확인
> 2. **환경변수 누락** (필수 설정 없음 → 시작 실패) — describe로 env 확인
> 3. **DB/외부 서비스 연결 실패** (시작 시 헬스체크) — 네트워크/방화벽 확인
> 4. **잘못된 명령어** (entrypoint 오타) — image의 ENTRYPOINT 확인
> 5. **권한 부족** (파일 쓰기 권한) — securityContext, fsGroup 확인

## 6. 학습 확인

- `Last State: Terminated` 의 의미는?
- `--previous` 옵션 없이 logs 명령이 실패한다면 그 이유는?
- Exit Code 0 인데 CrashLoop 면 무엇을 의심?

> **힌트**:
> - 직전에 떠있던 컨테이너가 종료됨. Reason/Exit Code가 종료 사유.
> - 현재 컨테이너가 아직 시작 안 됐거나 BackOff 대기 중이라 로그 없음. `--previous` 로 죽은 컨테이너 로그 봐야.
> - 의도적 정상 종료인데 K8s가 재시작 (RestartPolicy=Always) → CrashLoop. 또는 livenessProbe 실패. 또는 앱이 즉시 종료하는 entrypoint (예: `command: ["true"]`).
