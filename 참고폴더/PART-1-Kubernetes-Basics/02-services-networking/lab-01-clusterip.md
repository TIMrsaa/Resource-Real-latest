# Lab 01 — ClusterIP + Endpoints 관찰

## 학습 확인 포인트

- [ ] Service 만들면 Endpoints가 자동 생성됨을 확인했다
- [ ] 라벨 셀렉터로 Pod와 Service가 묶이는 메커니즘을 봤다
- [ ] Pod 죽으면 Endpoints가 자동 갱신되는 걸 봤다

> **🌱 핵심 개념 미리보기**
> - **Service**: 변하는 Pod IP를 안정적인 가상 IP(ClusterIP) 뒤에 숨겨주는 추상화 계층.
> - **ClusterIP**: 클러스터 내부 전용 IP. 외부에선 직접 접근 불가, Pod끼리 통신용.
> - **라벨 셀렉터**: Service의 `selector` 가 Pod의 라벨과 매칭 → Endpoints 자동 채움.
> - **Endpoints / EndpointSlice**: 실제 Pod IP 목록. Pod 추가/삭제 시 자동 갱신됨.
> - **kube-proxy**: 각 노드의 iptables/IPVS 룰을 만들어 ClusterIP → Pod IP 라우팅 담당.

## 1. 배포

```bash
kubectl apply -f manifests/clusterip.yaml
kubectl get svc web -o wide
kubectl get endpoints web        # 또는 endpointslices
```

기대:
```
NAME   TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE   SELECTOR
web    ClusterIP   10.100.123.45    <none>        80/TCP    20s   app=web

NAME   ENDPOINTS                                AGE
web    10.0.1.21:80,10.0.2.15:80,10.0.3.8:80    20s
```

→ **3개 Pod의 IP가 자동 등록**되어 있음.

> **🧠 Endpoints는 누가 채우나 — endpoint controller**
> kube-controller-manager 안의 endpoint controller 가 Service의 selector 와 Pod 라벨을 비교해 자동으로 Endpoints 객체를 채움.
> Pod가 Ready 상태가 돼야 Endpoints에 들어감 (readinessProbe 실패 시 빠짐 → 트래픽 차단).
> 1.21+ 에선 EndpointSlice 가 기본 (대규모 클러스터 성능 최적화). `kubectl get endpointslices` 로 확인.

## 2. 클러스터 내부에서 호출

```bash
kubectl run -it --rm dbg --image=alpine -- sh
# 안에서:
apk add --no-cache curl
curl http://web/                     # 짧은 이름
curl http://web.default/             # NS 명시
curl http://web.default.svc.cluster.local/   # FQDN
exit
```

세 가지 모두 동일하게 nginx 페이지 반환.

## 3. 부하 분산 확인

호스트네임을 보여주는 작은 트릭:

```bash
kubectl exec -it deploy/web -- sh -c \
  "echo \"\$HOSTNAME\" > /usr/share/nginx/html/index.html"
```

(Pod마다 별도 명령이 필요한 경우라 위 명령은 한 Pod에만 적용됨. 더 깔끔한 방법:)

```bash
kubectl get pods -l app=web -o name | while read p; do
  kubectl exec $p -- sh -c "echo $p > /usr/share/nginx/html/index.html"
done
```

이제 부하 분산 확인:

```bash
kubectl run -it --rm dbg --image=alpine -- sh
apk add --no-cache curl
for i in 1 2 3 4 5 6; do curl -s http://web/ ; done
exit
```

기대: 매번 다른 Pod 이름 반환 (라운드 로빈에 가까운 분배).

> **🧠 부하 분산은 정확한 라운드 로빈이 아님**
> 기본 kube-proxy 모드(iptables)는 확률 기반 (각 Pod에 동일 확률) 분배. 짧게 보면 들쭉날쭉, 길게 보면 균등.
> IPVS 모드면 진짜 라운드 로빈/least conn 등 알고리즘 선택 가능.
> 세션 유지 원하면 `service.spec.sessionAffinity: ClientIP`. 단, L7 routing 필요하면 Service만으론 부족 → Ingress 필요.

## 4. Pod 죽이고 Endpoints 갱신 관찰

watch:
```bash
watch -n1 kubectl get endpoints web
```

다른 터미널:
```bash
kubectl get pods -l app=web
kubectl delete pod <web-xxx>          # 임의 1개
```

watch 화면: ENDPOINTS 칸에서 IP 한 개가 빠지고, 잠시 후 새 Pod의 IP로 채워짐.

## 5. 셀렉터 변경하면? (의도적 망가뜨리기)

```bash
kubectl patch svc web --type=json -p='[{"op":"replace","path":"/spec/selector","value":{"app":"nonexistent"}}]'
kubectl get endpoints web
```

기대: ENDPOINTS 가 비어버림 (`<none>`).

→ Service는 살아있지만 호출하면 응답 없음. 흔한 디버깅 시작점.

> **🧠 "Service 호출했는데 응답 없음" 의 진단 순서**
> 1. `kubectl get endpoints <svc>` — 비었으면 selector/라벨 mismatch 또는 Pod readinessProbe 실패.
> 2. `kubectl describe svc <svc>` — Selector 확인 후 `kubectl get pods --show-labels` 와 대조.
> 3. Pod은 떠 있는데 Endpoints에 없음 = readiness 실패. `kubectl describe pod` 의 Conditions 확인.
> 운영에선 90% 가 selector 오타 또는 라벨 변경.

복구:
```bash
kubectl patch svc web --type=json -p='[{"op":"replace","path":"/spec/selector","value":{"app":"web"}}]'
```

## 학습 확인 질문

1. ClusterIP는 어디서 라우팅되는가? (커널 어떤 컴포넌트?)
2. Service의 selector를 바꾸지 않고 Endpoints를 직접 편집할 수도 있을까? 어떤 시나리오에서 필요할까?
3. `default` NS의 Pod가 `prod` NS의 `db` Service를 호출하려면 어떻게 해야 할까?

다음: [lab-02-nodeport-lb.md](./lab-02-nodeport-lb.md)
