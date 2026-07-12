# Lab 02 — Deployment + 롤링 업데이트

## 학습 확인 포인트

- [ ] Deployment → ReplicaSet → Pod 계층을 직접 관찰했다
- [ ] 롤링 업데이트가 어떻게 진행되는지 봤다
- [ ] 롤백을 해봤다

> **🌱 이 lab의 핵심 3계층**
> ```
>   Deployment (사용자가 만듦)
>     ↓ "원하는 상태: replicas 3, image=nginx:1.27"
>   ReplicaSet (Deployment가 자동 생성)
>     ↓ "이 라벨 가진 Pod 3개 유지"
>   Pod (ReplicaSet이 자동 생성)
>     ↓ 컨테이너 띄움
> ```
> 사용자는 **Deployment만 만지고**, 나머지는 K8s가 알아서.
> 새 버전 배포 = 새 ReplicaSet 만들고 Pod 점진 교체.

> **💡 일상 비유로 이해하기**
> 
> Deployment 의 롤링 업데이트는 **레스토랑 메뉴를 바꾸는 매니저**와 같습니다. 신메뉴 셰프(새 ReplicaSet)를 한 명씩 부르면서 동시에 옛 메뉴 셰프를 한 명씩 퇴근시키죠. 손님(트래픽) 끊김 없이 부드럽게 교체되고, 신메뉴가 별로면 즉시 옛 셰프를 다시 부르면(rollback) 됩니다.

## 1. Deployment 생성

```bash
kubectl apply -f manifests/deployment.yaml
kubectl get deploy,rs,pod -l app=web
```

> **`-l app=web`**: 라벨 셀렉터. `app=web` 라벨 가진 객체만 보기.
> Deployment, ReplicaSet, Pod이 모두 같은 라벨 가져 한 명령으로 다 봄.

기대 (조금 기다리면):
```
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/web   3/3     3            3           30s

NAME                             DESIRED   CURRENT   READY   AGE
replicaset.apps/web-7b8c9d6f5    3         3         3       30s

NAME                       READY   STATUS    RESTARTS   AGE
pod/web-7b8c9d6f5-aaaaa    1/1     Running   0          30s
pod/web-7b8c9d6f5-bbbbb    1/1     Running   0          30s
pod/web-7b8c9d6f5-ccccc    1/1     Running   0          30s
```

**관계 확인**:
- Deployment는 1개
- 그 아래 ReplicaSet 1개 (해시 7b8c9d6f5)
- 그 아래 Pod 3개 (모두 같은 ReplicaSet 해시 prefix)

> **🧠 ReplicaSet 이름의 해시는 어디서?**
> Pod template의 spec을 해싱한 값 (pod-template-hash 라벨).
> 이미지 변경 등으로 template이 바뀌면 → 새 해시 → 새 ReplicaSet 생성.
>
> = 같은 Deployment의 시간순 ReplicaSet 보관 (롤백용 히스토리).

## 2. ReplicaSet의 자가 치유 시연

```bash
kubectl get pods -l app=web
# 임의 pod 하나 골라서 삭제
kubectl delete pod web-7b8c9d6f5-aaaaa
kubectl get pods -l app=web --watch
```

기대: 즉시 새 Pod가 생성되어 다시 3개 유지.

> **🧠 자가 치유의 메커니즘 (control loop)**
> ```
>   ReplicaSet 컨트롤러:
>     while true:
>       현재 Pod 수 카운트 (selector 매칭)
>       if 부족: Pod 생성
>       if 많음: Pod 삭제
>       sleep
> ```
> 1초~수초 간격으로 반복. K8s의 모든 컨트롤러가 이 패턴.
>
> 즉 Pod을 삭제해도 ReplicaSet이 즉시 새 Pod 생성 → 사용자는 "결국엔 3개" 만 신경 쓰면 됨.

```bash
kubectl describe rs -l app=web | tail -20
```

`Events:` 에서 `Created pod` 가 보입니다.

## 3. 스케일 변경

```bash
kubectl scale deploy/web --replicas=5
kubectl get pods -l app=web
```

기대: Pod가 5개로 늘어남 (점진적 추가).

> **`kubectl scale`** vs YAML 수정: 일시적 변경엔 scale 명령. 영구 변경은 YAML의 replicas 수정 + apply.
> scale 명령으로 바꾼 값은 다음 apply 시 YAML의 값으로 다시 덮어씀 (주의).

```bash
kubectl scale deploy/web --replicas=2
kubectl get pods -l app=web
```

기대: Pod가 2개로 줄어듦 (오래된/임의의 Pod부터 삭제).

> **어떤 Pod부터 죽이나?** ReplicaSet의 기본 정책: cordoned 노드 → Pending → 시작 시간이 오래된 순 → 결정적 임의 순.
> 운영에서 특정 Pod 보존 원하면 PodDisruptionBudget 사용.

```bash
kubectl scale deploy/web --replicas=3   # 원래대로
```

## 4. 롤링 업데이트 시연

별도 터미널에서 미리 watch 시작:
```bash
kubectl get pods -l app=web --watch
```

원래 터미널:
```bash
kubectl set image deploy/web nginx=nginx:1.28
kubectl rollout status deploy/web
```

> **🧠 `kubectl set image` 가 트리거하는 일**
> 1. Deployment의 spec.template.spec.containers[0].image 가 변경됨
> 2. 새 pod-template-hash 계산 → 새 ReplicaSet 생성 (replicas=0 부터)
> 3. 새 RS replicas++, 옛 RS replicas-- 반복 (maxSurge/maxUnavailable 한도 내)
> 4. 새 RS가 목표 도달, 옛 RS가 0 → 롤링 완료
>
> = 무중단. 트래픽이 두 RS의 Pod에 나뉘어 가는 시간 잠깐 있음.

watch 터미널에서 본 흐름:
```
NAME                     READY   STATUS    AGE
web-7b8c9d6f5-aaaaa      1/1     Running   5m
web-7b8c9d6f5-bbbbb      1/1     Running   5m
web-7b8c9d6f5-ccccc      1/1     Running   5m
web-9d4f8a7e2-ddddd      0/1     Pending   0s    ← 새 RS의 Pod 등장
web-9d4f8a7e2-ddddd      0/1     ContainerCreating  1s
web-9d4f8a7e2-ddddd      1/1     Running   5s
web-7b8c9d6f5-aaaaa      1/1     Terminating  ← 옛 RS의 Pod 줄어듦
...
```

새 ReplicaSet이 만들어지고, 옛 ReplicaSet의 Pod가 점진적으로 사라지는 흐름이 보입니다.

```bash
kubectl get rs -l app=web
```

기대 (롤링 업데이트 끝난 후):
```
NAME              DESIRED   CURRENT   READY   AGE
web-7b8c9d6f5     0         0         0       6m  ← 옛 RS, replicas=0
web-9d4f8a7e2     3         3         3       1m  ← 새 RS, replicas=3
```

> **주목**: 옛 ReplicaSet은 사라지지 않습니다. 롤백을 위해 보관됩니다.

> **`spec.revisionHistoryLimit`**: 보관할 옛 RS 개수 (기본 10). 그 이상은 자동 삭제.
> 너무 많이 두면 etcd 부담 ↑, 너무 적으면 옛 버전으로 롤백 못 함.

## 5. 롤백

```bash
kubectl rollout history deploy/web
```

기대:
```
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

> **`CHANGE-CAUSE`**: 변경 사유 메모. apply 시 `--record` 또는 어노테이션으로 채울 수 있음:
> ```bash
> kubectl annotate deploy/web kubernetes.io/change-cause="image bump to 1.28"
> ```
> 운영에선 CI에서 자동으로 git SHA 채우는 패턴 권장.

```bash
kubectl rollout undo deploy/web
kubectl rollout status deploy/web
kubectl get rs -l app=web
```

기대: 옛 ReplicaSet의 replicas가 다시 3으로, 새 ReplicaSet은 0으로 → **빠른 롤백**.

> **🧠 롤백이 빠른 이유**
> 새로 이미지 pull/Pod 생성 X. 그저 옛 RS의 replicas 늘리고 새 RS의 replicas 줄임.
> = 옛 이미지가 노드에 캐시돼 있을 가능성 높음 → 거의 즉시.
>
> **`--to-revision` 옵션**: 특정 리비전으로:
> ```bash
> kubectl rollout undo deploy/web --to-revision=1
> ```

## 6. 롤링 업데이트 전략 미세조정

```bash
kubectl get deploy web -o yaml | yq '.spec.strategy'
```

기대:
```yaml
type: RollingUpdate
rollingUpdate:
  maxSurge: 1          # 평소보다 1개 많이까지 가능
  maxUnavailable: 0    # 평소보다 1개도 모자라면 안 됨
```

이 설정이면: 항상 최소 3개는 살아있고, 잠깐 4개까지 됩니다 (안전 우선).
빠르게 굴리고 싶으면 `maxSurge: 50%, maxUnavailable: 50%` 같은 식으로 조정.

> **🧠 두 옵션 의미**
> | 옵션 | 의미 |
> |------|------|
> | `maxSurge` | replicas 보다 최대 N개 더 생성 가능 (배포 속도 ↑) |
> | `maxUnavailable` | replicas 보다 최대 N개 모자랄 수 있음 (가용성 ↓ 허용) |
>
> 운영 패턴:
> - **무중단 우선**: maxSurge=25%, maxUnavailable=0 (4개면 잠깐 5개)
> - **빠른 배포**: maxSurge=50%, maxUnavailable=25%
> - **자원 절약**: maxSurge=0, maxUnavailable=25% (4개면 잠깐 3개로)

> **`type: Recreate` 옵션**: 모든 Pod 동시 죽이고 새 버전 띄움 (다운타임 발생).
> singleton 워크로드 (DB 등) 에 사용.

## 7. 정리

```bash
kubectl delete -f manifests/deployment.yaml
```

## 학습 확인 질문

1. Deployment를 삭제하면 ReplicaSet과 Pod는 어떻게 될까?
2. `kubectl scale` 과 `kubectl set image` 의 차이를 ReplicaSet 관점에서 설명?
3. `maxUnavailable: 0` 으로 설정하면 어떤 시나리오에서 롤링 업데이트가 멈출 수 있을까?

> **힌트**:
> 1. Cascade delete로 RS도 삭제 → Pod도 삭제. (백그라운드 정리. `--cascade=orphan` 옵션으로 자식 보존 가능.)
> 2. scale = 같은 RS의 replicas 변경 (새 RS 생성 X). set image = template 변경 → 새 RS 생성 + 점진 교체.
> 3. 노드 자원 부족으로 새 Pod이 Pending이면 옛 Pod도 죽일 수 없어서 (maxUnavailable=0) 영원히 대기. 또는 readinessProbe가 한참 후에 Ready 되는 앱에서 진행 매우 느림.

다음: [lab-03-namespace.md](./lab-03-namespace.md)
