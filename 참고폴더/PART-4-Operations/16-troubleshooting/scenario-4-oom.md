# 시나리오 4 — OOMKilled

> **🌱 OOMKilled 가 뭔가?**
> 컨테이너가 메모리 limit 초과 → 리눅스 커널의 OOM (Out Of Memory) Killer 가 강제 종료.
> 이때 Exit Code = 137 (= 128 + SIGKILL 9), Reason = OOMKilled.
>
> **언제 발생?**
> 1. 컨테이너 메모리 사용 > limits.memory → cgroup 한도 위반 → 그 컨테이너만 죽음
> 2. 노드 전체 메모리 부족 → 시스템 OOM Killer 가 가장 큰 Pod 선택 → 죽임 (예측 불가)
>
> 이 lab은 1번 케이스 (Pod의 limits 초과).

## 1. 재현

```bash
cat > /tmp/oom.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: oom-victim
spec:
  containers:
    - name: stress
      image: progrium/stress
      args: ["--vm", "1", "--vm-bytes", "200M", "--timeout", "300s"]
      resources:
        limits:
          memory: 100Mi          # 의도적으로 작게
EOF
kubectl apply -f /tmp/oom.yaml
sleep 30
```

> **stress 명령 옵션**:
> - `--vm 1` = 메모리 워커 1개
> - `--vm-bytes 200M` = 워커당 200MB 할당 시도
> - `--timeout 300s` = 5분 후 종료
>
> **함정**: limits=100Mi 인데 200M 할당 시도 → 즉시 OOM.

## 2. 증상

```bash
kubectl get pod oom-victim
```

```
NAME         READY   STATUS              RESTARTS   AGE
oom-victim   0/1     CrashLoopBackOff    2          45s
```

> **CrashLoopBackOff 처럼 보임**: OOM 죽으면 컨테이너 재시작 → 또 OOM → 또 재시작 → BackOff 패턴.
> = OOM도 CrashLoop의 하위 케이스.

## 3. 진단

```bash
kubectl describe pod oom-victim | grep -A5 'Last State\|Reason\|Exit Code'
```

기대:
```
Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
```

`Reason: OOMKilled` + `Exit Code: 137` (SIGKILL by OOM killer) 가 결정적.

> **🧠 OOMKilled 식별**: `Last State` 의 Reason이 OOMKilled. 이건 K8s가 자동 감지해서 표기.
> Exit 137 만 보면 외부 SIGKILL일 수도 있어 모호. **Reason 까지 봐야 확실**.

## 4. 직전 로그 (있다면)

```bash
kubectl logs oom-victim --previous
```

OOM 직전 메시지 (있다면) 또는 stress 의 출력 일부.

> **OOM은 SIGKILL 이라 graceful shutdown 불가**. 앱이 마지막 메시지 출력 못 함. 그래서 보통 로그가 의미 없음.
> Java/Go의 heap dump도 못 남김 (SIGTERM이면 가능, SIGKILL은 즉사).

## 5. 메트릭 확인 (Container Insights / Prometheus 가 떠있으면)

```bash
# Prometheus
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090
```

```
container_memory_working_set_bytes{pod="oom-victim"}
```

→ limits (104857600 bytes = 100Mi) 에 닿는 순간 OOMKill.

> **🧠 메모리 메트릭 종류**
> | 메트릭 | 의미 |
> |--------|------|
> | `container_memory_usage_bytes` | 캐시 포함 (가장 큰 값) |
> | `container_memory_working_set_bytes` | OOM 판단 기준 (캐시 일부 제외, 실제 활성 메모리) |
> | `container_memory_rss` | RSS (Resident Set Size, 실제 물리 메모리) |
>
> OOM 분석엔 `working_set` 가 정답. usage 는 캐시 포함이라 과대평가.

## 6. 해결

```bash
kubectl delete pod oom-victim
```

운영에선:
- limits 를 실제 사용량 기반으로 조정
- 메모리 leak 점검 (heap dump, profiling)
- requests <= 평균, limits >= peak 정도로

> **🧠 운영에서 limits 정하는 법**
> 1. 부하 테스트 + 메트릭 수집 → peak 메모리 확인
> 2. limits = peak * 1.3 (30% 여유)
> 3. requests = peak * 0.7 (under-commit, 노드 효율적 활용)
>
> 실측 없이 추측으로 정하면 OOM 또는 자원 낭비.

> **주의**: requests=limits 가 가장 안전 (Guaranteed QoS). 단 over-provisioning 위험.

> **🧠 QoS Class 3종**
> | QoS | 조건 | 노드 압박 시 |
> |-----|------|-------------|
> | **Guaranteed** | 모든 컨테이너 requests=limits, 모두 설정 | 마지막에 죽음 (가장 안전) |
> | **Burstable** | 일부만 설정 또는 requests<limits | 중간 |
> | **BestEffort** | requests/limits 둘 다 미설정 | 가장 먼저 죽음 |
>
> **`kubectl get pod -o jsonpath='{.status.qosClass}'`** 로 확인.
> stateful (DB 등) → Guaranteed 권장. stateless 일반 앱 → Burstable.

## 7. limits 없으면 어떤 일이?

```yaml
resources:
  requests: { memory: 100Mi }
  # limits 없음
```

→ 노드 메모리가 부족할 때 시스템 OOM killer 가 가장 큰 메모리 Pod 부터 종료. 예측 불가능 → **반드시 limits 권장**.

> **🧠 limits 없을 때의 위험**
> 한 Pod이 메모리 leak → 무한 증가 → 노드 전체 메모리 고갈 → 시스템 OOM → 다른 Pod까지 영향.
> = 한 Pod의 버그가 노드 전체를 마비시킴.
>
> **단**: Java 앱은 `-Xmx` 로 명시적 한도 가능. Go 앱은 GC가 limits 고려 (GOMEMLIMIT 환경변수, 1.19+).

## 학습 확인

- Exit Code 137 의 두 가지 의미는?
- requests > limits 가 가능한가? (NO. 왜?)
- VPA (Vertical Pod Autoscaler) 가 OOM 방지에 도움 되는 시나리오는?

> **힌트**:
> - (a) cgroup OOM (limits 초과 → 컨테이너만 죽음, Reason=OOMKilled). (b) 외부 SIGKILL (수동 kill, 노드 종료 등 → Reason=Error or 다른 것).
> - 불가. K8s API가 거부. 의미상 "최소 보장(requests)이 최대 한도(limits)보다 클 수는 없음".
> - 트래픽 패턴이 점진적 증가하는 앱. VPA가 사용량 보고 limits/requests 자동 상향. 단 Pod 재시작 필요 (in-place update는 베타).
