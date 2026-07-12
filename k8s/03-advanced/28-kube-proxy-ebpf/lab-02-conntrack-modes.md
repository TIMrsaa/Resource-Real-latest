# Lab 02 — conntrack 관찰과 모드의 풍경

## Step 1. conntrack 엔트리 — "기억된 변환" 보기

터미널 1 (노드):
```bash
NODE=$(kubectl get pod -l app=chain -o jsonpath='{.items[0].spec.nodeName}')
kubectl debug node/$NODE -it --image=public.ecr.aws/docker/library/busybox:stable
```

```sh
chroot /host
# Service IP로의 연결을 추적 준비
SVC_IP=<lab-01의 SVC_IP>
conntrack -L 2>/dev/null | grep $SVC_IP || echo "(아직 없음)"
```

터미널 2 (클라이언트 — 같은 노드에 뜨도록 nodeName 지정해도 좋습니다):
```bash
kubectl run cc --rm -it --restart=Never --image=public.ecr.aws/docker/library/busybox:stable -- \
  sh -c 'wget -qO- http://chain/hostname; sleep 30'
```

터미널 1에서 (클라이언트가 살아있는 30초 안에):
```sh
conntrack -L 2>/dev/null | grep "dport=80" | head -3
```

예상 출력 (한 줄 해석):
```
tcp ... src=192.168.c.c dst=172.20.x.x sport=41234 dport=80 \
        src=192.168.p.p dst=192.168.c.c sport=8080 dport=41234 ...
        └ 원래 방향 (Service IP로) ┘  └ 역방향 (실제 Pod가 응답) ┘
```

✅ **한 엔트리에 양방향 변환이 다 들어 있습니다** — "응답 규칙은 없습니다, 기억이 있다"의 물증. 이 테이블이 곧 NetworkPolicy stateful(모듈 15)의 토대이기도 합니다.

## Step 2. conntrack 용량 — 한도와 현재

```sh
sysctl net.netfilter.nf_conntrack_max
cat /proc/sys/net/netfilter/nf_conntrack_count
```

운영 감각: count가 max의 80%를 넘보면 — 새 연결이 무작위로 드롭되기 시작합니다("간헐 타임아웃"). 신호 메트릭: `node_nf_conntrack_entries`. 대량 단명 커넥션 워크로드(프록시, 스크레이퍼)가 주범.

## Step 3. kube-proxy의 설정과 메트릭 훔쳐보기

```sh
# kube-proxy가 어떤 모드로 도는지
ps aux | grep kube-proxy | head -1
cat /var/lib/kube-proxy-config/config 2>/dev/null | grep -A2 "mode" || echo "(EKS는 configmap 기반)"
exit; exit
```

```bash
kubectl get configmap -n kube-system kube-proxy-config -o yaml 2>/dev/null | grep mode || \
kubectl get configmap -n kube-system kube-proxy -o yaml | grep -i mode
# 동기화 성능 메트릭 (규칙 재작성에 걸린 시간)
kubectl get --raw /api/v1/namespaces/kube-system/pods/$(kubectl get pods -n kube-system -l k8s-app=kube-proxy -o jsonpath='{.items[0].metadata.name}')/proxy/metrics 2>/dev/null \
  | grep sync_proxy_rules_duration | tail -3 || echo "(메트릭 접근은 환경에 따라 제한)"
```

`sync_proxy_rules_duration_seconds`가 커지는 추세 = iptables 규칙 갱신이 버거워지는 신호 — IPVS/nftables 검토의 정량 근거.

## Step 4. 모드 전환의 풍경 (개념 + 명령 카탈로그)

공유 클러스터 모드 전환은 하지 않습니다. 각 모드에서 "보는 법"만 카탈로그로:

| 모드 | 규칙을 보는 명령 | 분배 확인 |
|------|------------------|----------|
| iptables | `iptables -t nat -L KUBE-SVC-...` | statistic probability |
| IPVS | `ipvsadm -Ln` | 가상서버별 백엔드 표 + 알고리즘(rr 등) |
| nftables | `nft list table ip kube-proxy` | verdict map |
| Cilium eBPF | `cilium service list` / `bpftool map` | BPF 맵 |

> kind(기여자 트랙)에서 `--proxy-mode=ipvs`/`nftables`로 클러스터를 만들어 위 명령들을 직접 비교해보는 것을 권합니다 — 로컬이라 무엇을 부숴도 안전합니다.

## Step 5. externalTrafficPolicy 미리 보기

```bash
kubectl patch svc chain -p '{"spec":{"type":"NodePort","externalTrafficPolicy":"Local"}}'
kubectl get svc chain -o jsonpath='{.spec.externalTrafficPolicy}'; echo
```

Local의 의미: 이 노드로 온 외부 트래픽은 **이 노드의 chain Pod로만** (없으면 드롭 — LB 헬스체크가 그 노드를 빼줘야 함). 효과: 추가 홉 제거 + **클라이언트 실제 IP 보존** (SNAT 생략). ALB/NLB와의 조합은 eks 파트 14에서 실측합니다.

## 정리

```bash
bash cleanup.sh
```
