# 시나리오 5 — Service 호출 무응답

> **🌱 Service가 무응답일 때 점검할 4단계**
> ```
>   클라이언트 → DNS 해석 → ClusterIP → kube-proxy iptables → endpoint 중 1개 → Pod
> ```
> 이 흐름의 어느 단계든 깨지면 무응답. 단계별로 절단해 어디서 깨졌는지 봐야.
>
> 본 시나리오의 핵심: **Endpoints 객체** = "Service가 가리키는 실제 Pod IP 목록".
> Endpoints가 비어있으면 Service는 가상 IP만 있고 트래픽 보낼 곳이 없음.

## 1. 재현

Service 의 selector 를 의도적으로 잘못 설정:
```bash
kubectl create deploy svc-test --image=nginx --replicas=2
kubectl expose deploy svc-test --port=80 --selector=app=does-not-exist
sleep 10
```

> **`kubectl expose`**: 기존 워크로드를 Service로 노출하는 단축 명령. YAML 안 만들고 즉시 생성.
> 여기선 `--selector` 를 일부러 잘못 박음.

## 2. 증상

```bash
kubectl run -it --rm dbg --image=alpine -- sh -c "apk add -q curl && curl -m 5 http://svc-test/ && echo OK"
```

기대:
```
curl: (28) Connection timed out after 5001 milliseconds
```

> **`-m 5`**: 5초 타임아웃. `--rm` = 컨테이너 종료 시 자동 삭제. `-it` = TTY 부착.
> 디버깅용 일회성 Pod 패턴 (자주 씀).

## 3. 진단 절차

### 3.1 Endpoints 확인

```bash
kubectl get endpoints svc-test
```

기대:
```
NAME       ENDPOINTS   AGE
svc-test   <none>      1m
```

→ Endpoints 가 비어있음. **이게 핵심 단서**.

> **🧠 Endpoints 객체란?**
> Service가 만들어지면 K8s가 자동으로 같은 이름의 Endpoints 객체 생성.
> 이 Endpoints가 "Service의 selector에 매칭된 + Ready인 Pod IP 목록".
> kube-proxy가 이 목록을 보고 iptables 룰 만듦.
>
> Endpoints가 비어있다 = "트래픽 보낼 Pod이 없다" = Service는 가상 IP만 있고 실체 없음.

### 3.2 Service selector 확인

```bash
kubectl get svc svc-test -o yaml | yq '.spec.selector'
```

기대:
```yaml
app: does-not-exist
```

### 3.3 실제 Pod 의 라벨 확인

```bash
kubectl get pods --show-labels | grep svc-test
```

기대:
```
svc-test-xxx   ...   app=svc-test,pod-template-hash=...
```

→ Service 가 찾는 라벨 `app=does-not-exist` 와 Pod 의 라벨 `app=svc-test` 불일치.

> **🧠 Service selector vs Pod labels 매칭**
> - Service.spec.selector: AND 매칭. 모든 키-값이 Pod labels에 다 있어야 매칭.
> - 하나라도 안 맞으면 → 그 Pod은 endpoint에서 제외.
> - **이 매칭은 정확히 일치만 됨** (regex/wildcard 불가).

## 4. 다른 가능 원인들

| 증상 | 진단 |
|------|------|
| Endpoints 있는데 timeout | Pod readinessProbe 실패 → Endpoints 에서 자동 제외 |
| ClusterIP 자체에 응답 없음 | kube-proxy 죽음 (`kubectl get pods -n kube-system -l k8s-app=kube-proxy`) |
| DNS 해석 실패 | CoreDNS Pod 상태 |
| Cross-NS 호출 안 됨 | FQDN 사용 여부 (`<svc>.<ns>.svc.cluster.local`) |

> **🧠 readinessProbe 와 Endpoints 의 관계**
> Pod이 만들어졌어도 readinessProbe 실패면 → "아직 트래픽 받을 준비 안 됨" → Endpoints에서 자동 제외.
> Pod READY 컬럼 `0/1` 이면 의심.
>
> ```bash
> kubectl get pods -o wide   # READY 컬럼 확인
> kubectl describe pod <name> | grep -A5 'Readiness'  # probe 결과
> ```

> **🧠 DNS 해석 단계 디버깅**
> ```bash
> kubectl run -it --rm dbg --image=alpine -- sh
> # 안에서:
> nslookup svc-test
> # 응답 없으면 CoreDNS 문제
> nslookup svc-test.default.svc.cluster.local
> # FQDN으로 시도
> ```
>
> CoreDNS Pod 확인:
> ```bash
> kubectl get pods -n kube-system -l k8s-app=kube-dns
> kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20
> ```

## 5. 해결

```bash
# 셀렉터 수정
kubectl patch svc svc-test --type=merge -p '{"spec":{"selector":{"app":"svc-test"}}}'

# 다시 호출
kubectl run -it --rm dbg --image=alpine -- sh -c "apk add -q curl && curl -m 5 http://svc-test/ | head -3"
```

> **`kubectl patch --type=merge`**: spec 일부분만 덮어씀. 전체 YAML 안 다시 적용.

## 6. 정리

```bash
kubectl delete deploy svc-test
kubectl delete svc svc-test
```

## 학습 확인

- Endpoints 가 자동 갱신되는 trigger 는?
- readinessProbe 가 실패한 Pod 가 Endpoints 에서 제외되는 동작이 의미하는 것은?
- Service의 selector 와 Pod 의 라벨이 일치한다고 가정할 때, Endpoints 가 비어있을 또 다른 원인은?

> **힌트**:
> - Pod 생성/삭제, Pod 라벨 변경, Pod readiness 상태 변경. 각 이벤트가 endpoint controller를 트리거.
> - "트래픽을 안전하게 받을 수 있는 시점에만 LB pool에 등록" = 무중단 배포의 핵심. 새 Pod이 부팅 중일 때 트래픽 안 가게.
> - 모든 Pod의 readinessProbe 실패. 또는 모든 Pod이 다른 NS에 있음 (Service는 같은 NS만 매칭). 또는 EndpointSlice가 손상됨 (드물지만).
