# Lab 02 — CPU 트리거 ScaledObject

> **🌱 가장 단순한 KEDA 예제 — CPU 부하 → Pod 자동 증가**
> 사실 이건 HPA 만으로도 가능. 하지만 KEDA로 시작하면:
> - **scale-to-zero** 가능 (HPA는 안 됨)
> - 다른 트리거(SQS, Kafka)와 동일한 ScaledObject 문법으로 통일
>
> 이 lab의 의도: ScaledObject ↔ HPA의 자동 변환을 눈으로 확인.

## 1. 적용

```bash
kubectl apply -f manifests/cpu-scaler.yaml
kubectl get scaledobject,hpa,deploy
```

기대:
```
NAME                              SCALETARGETKIND  SCALETARGETNAME  ACTIVE  AGE
scaledobject.keda.sh/cpu-demo     Deployment       cpu-demo         True    10s

NAME                                          REFERENCE
horizontalpodautoscaler.autoscaling/keda-hpa-cpu-demo  Deployment/cpu-demo
```

→ KEDA 가 자동으로 HPA 를 만듦 (`keda-hpa-<scaledobject-name>`).

> **🧠 ScaledObject가 만드는 것**
> 사용자가 ScaledObject 1개 적용 → KEDA Operator가:
> 1. **HPA 생성**: `keda-hpa-<name>`. metrics는 external 타입으로 KEDA metrics-apiserver 가리킴
> 2. **ExternalMetric** (CRD): metrics-apiserver가 응답할 메트릭 정의
> 3. **트리거별 폴링**: pollingInterval(15초)마다 SQS/Kafka/CPU 등 조회
>
> = ScaledObject 삭제 시 위 3개 자동 정리. 깔끔.

## 2. 부하 확인 (stress 가 자체적으로 CPU 100% 발생시킴)

watch:
```bash
watch -n3 'kubectl get hpa keda-hpa-cpu-demo; echo; kubectl get pods -l app=cpu-demo'
```

기대 (1~3분 후):
```
NAME                  REFERENCE             TARGETS    MINPODS  MAXPODS  REPLICAS
keda-hpa-cpu-demo     Deployment/cpu-demo   95%/50%    1        10       4    ← 스케일 업

NAME                          STATUS
cpu-demo-xxx-aaa              Running
cpu-demo-xxx-bbb              Running
cpu-demo-xxx-ccc              Running
cpu-demo-xxx-ddd              Running
```

> **`TARGETS` 컬럼 읽는 법**: `현재값/목표값`. 95%/50% = 현재 CPU 95%, 목표 50%. 초과 → scale up.
> HPA는 `desired = ceil(currentReplicas * (current/target))` 공식으로 replicas 계산.
> 95/50 ≈ 1.9 배수 → 1 replica 면 → ceil(1*1.9) = 2 → 다음 사이클 4...

## 3. stress 명령 종료 시 (5분 후 자동 종료)

stress 컨테이너의 `--timeout 300s` 가 끝나면 CPU 0% → KEDA cooldown 1분 후 → 1 replica 로 축소.

또는 강제 부하 종료:
```bash
kubectl exec -it deploy/cpu-demo -- pkill stress 2>&1 || true
```

> **`2>&1 || true`**:
> - `2>&1` = stderr를 stdout에 합침
> - `|| true` = 명령 실패해도 무시 (이미 죽은 stress면 pkill 실패. 그래도 진행)

watch 화면:
```
TARGETS    REPLICAS
20%/50%    4
20%/50%    3
20%/50%    2
20%/50%    1     ← 다시 minReplicaCount
```

> **🧠 Scale Down 이 점진적으로 일어나는 이유**
> HPA는 안정성 위해 stabilization window 적용:
> - scale up: 즉시 (트래픽 폭증 대응)
> - scale down: 기본 5분간 안정화 (튕김 방지)
>
> KEDA의 `cooldownPeriod` 가 이 stabilization을 미세 조정.

## 4. ScaledObject 살펴보기

```bash
kubectl describe scaledobject cpu-demo
```

`Status` 에서 트리거 메트릭 / HPA 이름 확인.

> **`status.conditions` 보기**:
> - `Ready` : 트리거 평가 가능 (true 면 정상)
> - `Active`: 현재 minReplica 위로 스케일 중
> - `Fallback`: 트리거 실패 시 fallback 동작 중

## 5. 정리

```bash
kubectl delete -f manifests/cpu-scaler.yaml
```

## 학습 확인 질문

1. KEDA 가 만든 HPA 의 이름 패턴은?
2. ScaledObject 를 삭제하면 자동 생성된 HPA 와 Deployment 는 어떻게 되는가?
3. CPU/Memory 트리거는 metrics-server 가 필요한가?

> **힌트**:
> 1. `keda-hpa-<scaledobject-name>` (예: `keda-hpa-cpu-demo`).
> 2. HPA는 자동 삭제 (KEDA가 만든 것이라). Deployment는 그대로 (사용자가 만든 것). 마지막 replicas 값으로 유지.
> 3. **필요**. CPU/Memory는 metrics-server 의 메트릭을 KEDA가 재사용. metrics-server 없으면 트리거 실패.

다음: [lab-03-cron-scaler.md](./lab-03-cron-scaler.md)
