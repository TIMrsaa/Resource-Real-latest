# Lab 03 — Namespace 격리 시연

## 학습 확인 포인트

- [ ] 같은 이름의 리소스가 다른 NS에서는 충돌 없이 존재 가능함을 확인했다
- [ ] NS 간 통신 방법(짧은 이름 vs FQDN)을 안다
- [ ] `kubectl config set-context --current --namespace` 로 기본 NS를 바꿔봤다

> **🌱 핵심 개념 미리보기**
> - **Namespace**: 클러스터 안의 가상 격리 공간. 팀/환경(dev/prod)/프로젝트 단위로 분리.
> - **이름 충돌 회피**: 같은 이름의 리소스도 NS가 다르면 공존 가능 (예: 두 팀이 모두 `web` Deployment).
> - **FQDN**: `<svc>.<ns>.svc.cluster.local` — 다른 NS의 Service 호출에 필수.
> - **Cluster-scoped vs Namespaced**: Node, PV, ClusterRole 같은 리소스는 NS 격리 안 됨 (클러스터 전체 영향).
> - **`-n` vs `-A`**: `-n <ns>` 는 특정 NS만, `-A` 는 모든 NS 통합 조회.

> **💡 일상 비유로 이해하기**
> 
> Namespace 는 **아파트의 동(棟)** 같습니다. 101동 1503호와 102동 1503호가 같은 호수여도 충돌 없이 공존하죠. 같은 동 안에선 "1503호" 라고만 해도 통하지만, 다른 동에 가려면 "102동 1503호" 라고 풀네임(FQDN)을 불러야 합니다.

## 1. Namespace 만들기

```bash
kubectl apply -f manifests/namespace.yaml
kubectl get ns
```

기대: `lab-team-a`, `lab-team-b` 두 개 추가됨.

## 2. 같은 이름의 Deployment를 두 NS에 배포

```bash
# team-a
kubectl apply -n lab-team-a -f manifests/deployment.yaml

# team-b
kubectl apply -n lab-team-b -f manifests/deployment.yaml

kubectl get deploy -A | grep web
```

기대:
```
lab-team-a    web    3/3   3   3   30s
lab-team-b    web    3/3   3   3   25s
```

→ **같은 이름** `web` 이지만 충돌 없이 양쪽에 존재.

> **🧠 NS는 리소스 격리지 보안 격리가 아님**
> 기본 설정에선 다른 NS의 Pod도 IP만 알면 호출 가능 (네트워크 레벨 차단 X).
> 진짜 격리 원하면 NetworkPolicy 추가해야 함. NS는 "이름 공간 + RBAC 경계 + 리소스 쿼터 단위" 라고 이해하면 정확함.

## 3. 기본 NS 바꿔보기

```bash
kubectl config set-context --current --namespace=lab-team-a
kubectl get pods       # team-a의 Pod만 보임

kubectl config set-context --current --namespace=lab-team-b
kubectl get pods       # team-b의 Pod만 보임

kubectl config set-context --current --namespace=default
```

## 4. Service 만들고 NS 간 호출 시도

team-a에 Service 추가:
```bash
kubectl create service clusterip web -n lab-team-a --tcp=80:80
```

디버그 Pod 띄우기 (같은 NS에서):
```bash
kubectl run -it --rm dbg --image=alpine -n lab-team-a -- sh
# 안에서:
apk add --no-cache curl
curl http://web/        # 짧은 이름 OK
exit
```

같은 디버그 Pod를 다른 NS에서 띄워서 호출:
```bash
kubectl run -it --rm dbg --image=alpine -n lab-team-b -- sh
# 안에서:
apk add --no-cache curl

# 짧은 이름은 자기 NS의 web을 찾기 때문에 → team-b의 web으로 감
curl http://web/

# team-a의 web에 가려면 FQDN
curl http://web.lab-team-a.svc.cluster.local/

exit
```

> **결론**: 같은 NS면 짧은 이름, 다른 NS면 FQDN(`<svc>.<ns>.svc.cluster.local`).

> **🧠 짧은 이름이 동작하는 이유 — search 도메인**
> Pod의 `/etc/resolv.conf` 에 `search <자기NS>.svc.cluster.local svc.cluster.local cluster.local` 자동 주입됨.
> 그래서 `curl http://web/` 시 `web.<자기NS>.svc.cluster.local` 부터 시도 → 자기 NS의 web을 먼저 찾음.
> 다음 lab(DNS) 에서 직접 확인.

## 5. 리소스를 NS 단위로 일괄 정리

```bash
kubectl delete ns lab-team-a lab-team-b
```

`kubectl delete ns <name>` 만으로 그 NS 안의 모든 리소스가 삭제됩니다 → **격리의 또 다른 효과**.

> **🧠 `delete ns` 는 강력하지만 위험함**
> NS 안의 모든 Pod, Service, PVC, Secret, ConfigMap 까지 한방에 사라짐 → 운영 NS에 실수 시 복구 불가.
> 운영에선 RBAC으로 `delete namespaces` 권한을 매우 제한하거나, OPA/Kyverno 정책으로 prod 류 NS 보호.
> 또한 stuck 상태로 안 사라질 때(`finalizer` 잔존) 가 종종 있음 → 검색 키워드 "stuck terminating namespace".

## 학습 확인 질문

1. Node, PersistentVolume, ClusterRole 은 Namespace로 격리될까?
2. 같은 NS의 다른 Service에 접근하는 짧은 이름 형태는?
3. `kubectl delete ns my-ns` 의 위험성을 한 가지 들어보세요.

다음: [quiz.md](./quiz.md)
