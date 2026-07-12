# 흔한 함정 7선 — 16. Troubleshooting

## 1. CrashLoop 인데 `--previous` 없이 logs 봐서 "로그 없음" 이라고 결론

**증상**: `kubectl logs <pod>` 했는데 빈 출력 → "로그 안 남았네" 하고 다른 곳 뒤짐.

**원인**: CrashLoopBackOff 상태에선 **현재 컨테이너가 아직 시작 안 했거나 BackOff 대기 중**. 일반 logs 는 현재 인스턴스 대상. 죽은 직전 인스턴스 로그는 `--previous` 로만 접근.

**해결**:
```bash
kubectl logs <pod> --previous
# 또는 짧게
kubectl logs <pod> -p
```

> **🧠 CrashLoop 디버깅의 90% 는 `--previous` 한 줄로 해결.**
> 이 옵션을 모르면 며칠을 헤맴. 이 시리즈에서 가장 중요한 한 가지를 꼽으라면 이것.

---

## 2. Events 안 읽고 `kubectl logs` 부터 던짐

**증상**: ImagePullBackOff / Pending / OOMKilled 같은 K8s 단계의 문제인데 앱 로그만 본다.

**원인**: Pod 가 아예 시작도 안 했으면 앱 로그가 없음. 원인은 K8s 가 이미 Events 에 적어놨음.

**해결**: 트러블슈팅 첫 명령은 항상 `describe`:
```bash
kubectl describe pod <name> | tail -20
# 또는
kubectl get events --sort-by='.lastTimestamp' | tail -20
```

> **🧠 "logs 부터" 가 아니라 "Status → Events → logs" 순서.**
> Status 가 Running 도 아닌데 logs 보면 시간 낭비.

---

## 3. Exit Code 137 을 무조건 OOMKilled 로 단정

**증상**: Exit Code 137 보고 "메모리 limit 올리자" 하고 끝냄 → 또 죽음.

**원인**: 137 = SIGKILL (128+9). OOM Killer 가 흔하지만 **외부 강제 kill 도 137**.
- 컨테이너 자체 limit 초과 → cgroup OOM (Reason=OOMKilled)
- 노드 전체 메모리 부족 → 시스템 OOM Killer (Reason=Error 또는 OOMKilled)
- 외부에서 docker/crictl 로 SIGKILL → Reason=Error

**해결**: Exit Code 와 **Reason 둘 다** 보기:
```bash
kubectl get pod <name> -o jsonpath='{.status.containerStatuses[0].lastState.terminated}' | jq
```

`reason`, `exitCode`, `signal` 다 확인.

---

## 4. Pod Pending 인데 노드 자원만 보고 끝

**증상**: `kubectl top nodes` 봤더니 자원 여유 있음 → "근데 왜 Pending?" 헤맴.

**원인**: Pending 의 원인은 자원 외에도 많음:
- nodeSelector / affinity 매칭 실패
- taint 견딜 toleration 없음
- topology spread constraints
- PVC 바인딩 실패 (WaitForFirstConsumer)
- Pod IP 한도 도달 (VPC CNI prefix 모드 미사용)

**해결**: `kubectl describe pod` 의 **Events 메시지 그대로 읽기**:
```
0/3 nodes are available:
  1 Insufficient cpu,
  2 had untolerated taint {key=value:NoSchedule}
```
이 메시지에 노드별 정확한 거절 이유가 있음. 추측 X.

> **🧠 K8s 스케줄러는 Pending 이유를 매우 친절하게 적음.** 그 메시지 한 줄이 전부.

---

## 5. Service 무응답인데 Pod 부터 본다

**증상**: 앱 호출 안 됨 → Pod 안에 들어가서 디버깅 → 정상. 더 헤맴.

**원인**: Service ↔ Pod 사이 깨짐. Pod 자체는 정상.

**해결**: 위에서 아래로 절단:
```bash
# 1. Service 존재?
kubectl get svc <name>
# 2. Endpoints 채워져 있어?       ← 여기가 90% 정답
kubectl get endpoints <name>
# 3. selector 매칭 확인
kubectl get pods -l <selector>
# 4. Pod readiness 확인
kubectl get pod <name> -o wide
```

**Endpoints 가 비어있다 = selector 불일치 OR Pod 가 NotReady**. Pod 안 들어가도 즉시 답.

---

## 6. 노드 NotReady 일 때 `kubectl drain` 부터 던짐

**증상**: 노드 NotReady → 즉시 drain 명령 → 더 큰 장애 (Pod 옮길 곳 없음).

**원인**: 원인 진단 전에 회복 액션. NotReady 가 일시적 (네트워크 깜빡)일 수도 있는데 영구 처리해버림.

**해결 절차**:
1. **먼저 진단** — `kubectl describe node <name>` 의 Conditions 확인
2. **Pod 영향 범위 파악** — `kubectl get pods -o wide --field-selector spec.nodeName=<node>`
3. **AWS 콘솔** 또는 SSM Session Manager 로 노드 자체 진단 (kubelet, 디스크, CNI)
4. **회복 불가 판단 후** 에야 cordon → drain → terminate

> **🧠 "복구 액션 전에 진단" 은 운영 1원칙.**
> 5분 깜빡이는 노드를 drain 하면 5분이 30분이 됨.

---

## 7. PVC Pending 을 PVC 만 보고 푼다

**증상**: PVC Pending → StorageClass / CSI / 권한 다 봤는데 멀쩡 → 헤맴.

**원인**: `volumeBindingMode: WaitForFirstConsumer` (gp2/gp3 기본값) 일 때, **PVC 는 Pod 가 어떤 노드에 갈지 결정될 때까지 일부러 Pending**. Pod 가 다른 이유 (resource 부족, taint) 로 Pending 이면 PVC 도 영원히 Pending.

**해결**:
```bash
# PVC 가 아니라 그 PVC 를 쓰는 Pod 부터
kubectl get pods | grep <app>
kubectl describe pod <pod-using-pvc>
# Pod Events 에 진짜 원인 (예: Insufficient cpu) 있음
```

> **🧠 chicken-and-egg**: PVC 는 Pod 를 기다리고, Pod 는 자원을 기다림. **자원 문제부터 풀어야 PVC 도 풀림**.

---

## 부록 — 트러블슈팅 첫 30초 체크리스트

장애 신고 받자마자 던지는 명령들:

```bash
# 1. 영향 범위
kubectl get pods -A -o wide | grep -vE 'Running|Completed'

# 2. 노드 상태
kubectl get nodes
kubectl top nodes 2>/dev/null

# 3. 최근 이벤트 (전체 NS)
kubectl get events -A --sort-by='.lastTimestamp' | tail -20

# 4. 시스템 Pod
kubectl get pods -n kube-system | grep -vE 'Running|Completed'

# 5. 의심 Pod 상세
kubectl describe pod <name> -n <ns> | tail -30
```

이 5개로 80% 의 장애는 1차 분류 가능.

다음 모듈: [17-cost-optimization](../17-cost-optimization/)
