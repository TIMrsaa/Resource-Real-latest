# Lab 01 — 첫 Pod 배포

## 학습 확인 포인트

- [ ] Imperative vs Declarative 차이를 안다
- [ ] Pod의 라이프사이클 단계를 본 적이 있다
- [ ] `kubectl describe pod` 으로 이벤트를 읽을 수 있다

> **🌱 핵심 개념 미리보기**
> - **Pod**: K8s의 최소 배포 단위. 컨테이너 1개 또는 여러 개를 묶어 같은 네트워크/스토리지 공유함.
> - **Imperative vs Declarative**: 명령어로 즉시 만드는 방식 vs YAML로 "원하는 상태" 선언하는 방식. 실무는 후자.
> - **kubectl describe**: 사람이 읽기 좋은 상세 정보 + 이벤트 로그. 디버깅 1순위 도구.
> - **Pod IP**: 클러스터 내부에서만 유효한 IP. Pod이 죽으면 사라짐 → 그래서 Service가 필요해짐.
> - **단명함(ephemeral)**: Pod은 언제든 죽을 수 있음. 직접 만든 Pod은 죽으면 끝 → 다음 lab의 Deployment 동기.

> **💡 일상 비유로 이해하기**
> 
> Pod 직접 만들기는 **친구가 잠깐 와서 회의실 의자 하나 꺼내 앉는 것**과 같습니다. 의자(Pod)가 부서지면 아무도 다시 가져다주지 않아요. 그래서 실무에선 "의자 3개를 항상 유지해줘"라고 시키는 매니저(Deployment)가 필요합니다.

## 1. Imperative — 명령어로 즉시 띄우기

```bash
kubectl run hello-imperative --image=nginx:1.27 --port=80
```

> **🧠 `kubectl run` 은 그냥 Pod 한 개를 만듦**
> 옛날엔 `kubectl run` 이 Deployment를 만들었지만, 1.18+ 부터는 단순 Pod 생성으로 바뀜.
> = 컨트롤러 없는 "고아 Pod" → 죽으면 끝. 빠른 테스트용으로만 쓰는 이유.

확인:
```bash
kubectl get pods
kubectl get pod hello-imperative -o wide
```

기대:
```
NAME                READY   STATUS    RESTARTS   AGE
hello-imperative    1/1     Running   0          15s
```

## 2. Declarative — YAML로 띄우기 (실무 표준)

```bash
kubectl apply -f manifests/pod.yaml
```

같은 결과지만, **YAML 파일이 곧 인프라의 단일 소스 오브 트루스**가 됩니다. 이게 실무 표준.

> **🧠 왜 Declarative가 표준인가**
> YAML을 git에 올리면: 변경 이력 추적, 코드 리뷰, 자동 배포(GitOps), 재현성 모두 확보됨.
> `apply` 는 "이 상태가 되도록 해줘" 라서 같은 명령을 여러 번 실행해도 결과 동일 (idempotent).
> 반면 `kubectl run/create` 는 같은 명령 두 번 실행 시 "이미 있다" 에러 → 자동화 어려움.

```bash
kubectl get pods
```

기대:
```
NAME                READY   STATUS    RESTARTS   AGE
hello-pod           1/1     Running   0          10s
hello-imperative    1/1     Running   0          1m
```

## 3. 상세 정보 보기

### Describe — 사람이 읽기 쉬운 형태

```bash
kubectl describe pod hello-pod
```

주목해서 볼 부분:
- `Events:` 마지막 — 어떤 단계를 거쳤는지 보여줌
- `IP:` — Pod에 할당된 클러스터 내 IP
- `Node:` — 어느 노드에서 실행 중인지
- `Conditions:` — `PodScheduled`, `Ready` 등 상태

> **🧠 Events가 디버깅의 시작점**
> Pod이 안 뜨는 이유 90%는 Events 끝부분에 답이 있음. `ImagePullBackOff`, `FailedScheduling`, `OOMKilled` 등.
> EKS에선 특히 `FailedScheduling: ... no nodes available` (노드 자원 부족) 이 흔함 → Cluster Autoscaler 또는 Karpenter 가 해결.

### YAML — 머신이 읽는 전체 정의

```bash
kubectl get pod hello-pod -o yaml | less
```

`status:` 부분에 K8s가 채워 넣은 정보가 잔뜩 (할당된 IP, 호스트, 컨테이너 ID 등).

### JSONPath로 특정 필드만

```bash
kubectl get pod hello-pod -o jsonpath='{.status.podIP}'
echo  # 줄바꿈
kubectl get pod hello-pod -o jsonpath='{.spec.nodeName}'
```

## 4. 로그와 셸

### 로그 보기

```bash
kubectl logs hello-pod
kubectl logs hello-pod -f    # 실시간 follow
```

### 셸로 진입

```bash
kubectl exec -it hello-pod -- sh
# 안에서:
ls /
hostname
exit
```

## 5. Pod 안에서 테스트

```bash
# 다른 디버그 Pod 띄워서 hello-pod에 접근
kubectl run -it --rm dbg --image=alpine -- sh
# 안에서:
apk add --no-cache curl
curl <hello-pod의 IP>     # describe로 본 IP
exit
```

기대: HTML이 나옴 (nginx 기본 페이지).

## 6. Pod의 단명함 체험

```bash
kubectl delete pod hello-pod
kubectl get pods
```

**Pod가 사라졌습니다.** 자동으로 다시 만들어주는 컨트롤러가 없으면 끝. 이게 다음 lab의 동기.

> **🧠 운영에서 "Pod 직접 만들기" 는 사실상 없음**
> 실무에선 Deployment, StatefulSet, DaemonSet, Job 같은 컨트롤러를 통해 Pod을 만듦.
> 그래야 노드 다운/Pod 죽음 등 장애 시 K8s가 자동 복구함. 직접 만든 Pod은 디버깅/일회성 테스트 용도뿐.

## 7. 이번 lab 정리

```bash
kubectl delete pod hello-imperative
```

## 학습 확인 질문

1. `kubectl run` 과 `kubectl apply -f` 의 차이를 한 문장으로?
2. `kubectl describe pod` 출력 중 어디를 보면 "왜 Pending에 머물러 있는가" 를 알 수 있을까?
3. Pod가 죽으면 자동으로 살아나지 않는 이유는?

답은 [theory.md §1, §2](./theory.md) 에서.

다음: [lab-02-deployment.md](./lab-02-deployment.md)
