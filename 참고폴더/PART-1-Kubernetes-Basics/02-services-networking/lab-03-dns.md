# Lab 03 — CoreDNS 직접 질의

## 학습 확인 포인트

- [ ] Pod의 `/etc/resolv.conf` 가 어떻게 구성되는지 봤다
- [ ] CoreDNS Pod를 직접 확인했다
- [ ] dig/nslookup으로 Service DNS 레코드를 조회했다

> **🌱 핵심 개념 미리보기**
> - **CoreDNS**: K8s 클러스터 내부 DNS 서버. 모든 Pod의 nameserver 로 자동 주입됨.
> - **kube-dns Service**: CoreDNS Pod 앞에 있는 Service. 모든 Pod이 이 IP(보통 10.100.0.10) 로 DNS 질의.
> - **Service DNS 레코드**: `<svc>.<ns>.svc.cluster.local` 형태로 자동 생성됨.
> - **search 도메인**: 짧은 이름 입력 시 자동으로 붙여 시도하는 도메인 목록 (`/etc/resolv.conf`).
> - **ndots:5**: 점 5개 미만이면 search 도메인부터 시도 → 외부 도메인 조회 시 추가 쿼리 발생.

## 1. CoreDNS Pod 확인

```bash
kubectl get pods -n kube-system -l k8s-app=kube-dns
```

기대:
```
NAME                       READY   STATUS    RESTARTS   AGE
coredns-xxxxxxxxxx-aaaaa   1/1     Running   0          1d
coredns-xxxxxxxxxx-bbbbb   1/1     Running   0          1d
```

```bash
kubectl get svc -n kube-system kube-dns
```

기대:
```
NAME       TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   10.100.0.10   <none>        53/UDP,53/TCP,9153/TCP   1d
```

이 `10.100.0.10` 이 모든 Pod의 nameserver로 자동 주입됩니다.

> **🧠 CoreDNS도 그냥 Pod임 — 즉 죽을 수 있음**
> CoreDNS Pod 2개가 모두 죽으면 클러스터 전체 DNS 마비. → 신규 Pod이 service 못 찾고, kubelet이 image pull 못 함 (외부 DNS 도). EKS에선 보통 2~3 replicas + PodDisruptionBudget로 보호.
> 대규모 클러스터는 NodeLocal DNSCache (각 노드에 DNS 캐시 Pod 띄움) 추가해 부하 분산.

## 2. Pod의 resolv.conf 보기

```bash
kubectl run -it --rm dbg --image=alpine -- sh
# 안에서:
cat /etc/resolv.conf
```

기대:
```
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.100.0.10
options ndots:5
```

→ 모든 DNS 쿼리는 우선 10.100.0.10 (CoreDNS) 으로.

> **🧠 resolv.conf 는 누가 만드나 — kubelet**
> Pod 시작 시 kubelet이 생성. `dnsPolicy: ClusterFirst` (기본) 면 자동으로 CoreDNS 주소 + search 도메인 주입.
> hostNetwork Pod은 `dnsPolicy: ClusterFirstWithHostNet` 으로 명시해야 클러스터 DNS 사용 가능.
> 외부 DNS만 쓰고 싶으면 `dnsPolicy: Default` (노드의 resolv.conf 그대로 상속).

## 3. nslookup / dig 사용

```bash
# 알파인에 nslookup 설치
apk add --no-cache bind-tools

# Service 짧은 이름
nslookup web

# FQDN
nslookup web.default.svc.cluster.local

# 외부 도메인 (CoreDNS가 클러스터 외부 DNS로 forward)
nslookup google.com

# kube-dns 자체 조회
nslookup kube-dns.kube-system.svc.cluster.local
```

각 응답에서 IP가 어떻게 나오는지 비교.

## 4. SRV 레코드 (포트까지 포함)

```bash
nslookup -type=srv _http._tcp.web.default.svc.cluster.local
```

기대:
```
_http._tcp.web.default.svc.cluster.local  service = 0 100 80 web.default.svc.cluster.local.
```

→ Service의 `name: http` 가 있으면 SRV로도 노출됨. StatefulSet의 Headless Service에서 실용적.

## 5. ndots:5 옵션의 의미

```
options ndots:5
```

→ 도메인 이름에 점이 5개 이상이면 절대 도메인으로 즉시 조회, 적으면 search 도메인부터 차례로 시도.

**관찰**: `nslookup web` 은 search 첫 번째 도메인 `default.svc.cluster.local` 이 붙어 `web.default.svc.cluster.local` 로 시도 → 성공.

**부작용**: `google.com` 처럼 점이 1개면 ndots:5 조건 미달 → search 도메인부터 시도 → 1회 실패 후 절대 도메인으로 → **DNS 쿼리가 한 번 더 발생**. 대규모 클러스터에서 CoreDNS 부하 원인.

> **🧠 ndots:5 의 실제 영향 예**
> `google.com` 호출 시 search 도메인(default.svc, svc, cluster.local) 3개에 각각 시도 후 NXDOMAIN → 마지막에 절대 도메인으로 시도.
> = **외부 도메인 1개 호출에 DNS 쿼리 4번 발생**. 트래픽 많은 서비스면 CoreDNS QPS 급증 → 캐시 미스 + 타임아웃.
> 해결: 외부 도메인은 끝에 `.` 붙이거나 (`google.com.`), Pod별 ndots:1 설정.

해결 옵션:
```yaml
# Pod spec
dnsConfig:
  options:
    - name: ndots
      value: "1"
```

## 6. CoreDNS ConfigMap 살펴보기

```bash
kubectl get cm -n kube-system coredns -o yaml | yq '.data.Corefile'
```

대략:
```
.:53 {
    errors
    health
    kubernetes cluster.local in-addr.arpa ip6.arpa { ... }
    forward . /etc/resolv.conf
    cache 30
    ...
}
```

`forward . /etc/resolv.conf` → 클러스터 내부 도메인이 아니면 노드의 외부 DNS로 위임.

## 7. exit + 정리

```bash
exit
```

이 lab은 watch만 했으므로 별도 정리 없음.

## 학습 확인 질문

1. Pod에서 `nslookup web` 이 성공했는데 `nslookup web.default` 도 같은 결과를 줄까? 왜?
2. CoreDNS가 죽으면 무슨 일이 벌어지나? (워크로드는 어떻게 영향 받음?)
3. ndots:5 가 외부 도메인 조회 성능에 미치는 영향을 한 줄로?

다음: [quiz.md](./quiz.md)
