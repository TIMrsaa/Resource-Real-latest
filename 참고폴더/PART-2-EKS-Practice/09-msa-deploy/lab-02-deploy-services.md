# Lab 02 — 5개 서비스 배포

## 학습 확인 포인트

- [ ] 5개 서비스 모두 Ready
- [ ] ALB 자동 생성, frontend / order-service 에 라우팅
- [ ] ServiceMonitor 가 메트릭 scrape 시작

> **🌱 핵심 개념 미리보기**
> - **Ingress + ALB**: K8s `Ingress` 리소스 → AWS LB Controller 가 ALB 자동 생성. 호스트/경로 기반 L7 라우팅
> - **Service 종류**: `ClusterIP` (클러스터 내부용), `Headless` (`clusterIP: None` — DNS만 노출, gRPC/StatefulSet에 자주 쓰임)
> - **gRPC 통신**: `user-service:50051` 처럼 K8s DNS 로 서비스끼리 직접 호출 (HTTP 안 쓰고 바이너리 RPC)
> - **CrashLoopBackOff**: 컨테이너가 계속 죽고 다시 뜨는 상태. 본 lab의 `notification-service` 는 의존성(Kafka) 부재로 정상적으로 실패함
> - **ServiceMonitor cross-namespace**: `monitoring` NS의 Prometheus가 `order` NS Service까지 scrape 가능 (selector가 NS를 가로지름)

## 1. 적용 (lab-01에서 만든 /tmp/msa/ 사용)

```bash
# Namespace 먼저 (다른 매니페스트의 NS 참조 의존성)
kubectl apply -f /tmp/msa/base/namespace.yaml

# 나머지 모든 매니페스트 (서브디렉토리 포함)
kubectl apply -R -f /tmp/msa/

kubectl get pods -n order --watch
```

> **🧠 `-R` 플래그가 핵심**
> lab-01에서 `/tmp/msa/order/`, `/tmp/msa/user/`... 처럼 서비스별 서브디렉토리를 만들었기 때문에 `-R`(recursive) 없이 `-f /tmp/msa/` 만 주면 파일 0개 발견 → 아무것도 적용 안 됨.
> `-R` 은 디렉토리를 깊이우선 탐색해 모든 `.yaml`/`.yml`/`.json` 을 모아 한 번에 apply.
>
> Namespace 만 먼저 따로 적용한 이유: `kubectl apply` 가 파일 알파벳 순으로 처리하므로 `order/deployment.yaml` 이 `base/namespace.yaml` 보다 먼저 평가될 수 있음 → "namespace not found" 에러 회피.

기대 (몇 분 후):
```
NAME                                 READY   STATUS    RESTARTS   AGE
order-service-xxx-aaa                1/1     Running   0          1m
order-service-xxx-bbb                1/1     Running   0          1m
user-service-xxx-aaa                 1/1     Running   0          1m
user-service-xxx-bbb                 1/1     Running   0          1m
payment-service-xxx-aaa              1/1     Running   0          1m
notification-service-xxx-aaa         0/1     CrashLoopBackOff       ← 정상 (Kafka 없음)
frontend-xxx-aaa                     1/1     Running   0          1m
frontend-xxx-bbb                     1/1     Running   0          1m
```

> notification-service 는 Kafka 가 없어서 실패하는 게 **정상**. Part 3 모듈 13에서 Kafka 를 띄우면 정상 동작.

> **🧠 CrashLoopBackOff 의 메커니즘**
> 컨테이너가 죽으면 kubelet이 즉시 재시작 → 또 죽음 → 점점 백오프 간격 증가 (10s → 20s → 40s → ... 최대 5분).
> "Loop" 가 아니라 "BackOff" 가 핵심: K8s 가 무한 재시작으로 노드 자원을 낭비하지 않게 간격을 늘리는 것.
>
> 디버깅 순서: `kubectl logs -p <pod>` (이전 컨테이너 로그) → `kubectl describe pod` Events → 의존성/설정 확인.

## 2. Service 확인

```bash
kubectl get svc -n order
```

기대:
```
NAME                   TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)
frontend               ClusterIP   10.100.x.y      <none>        80/TCP
order-service          ClusterIP   10.100.x.y      <none>        80/TCP, 9090/TCP
user-service           ClusterIP   10.100.x.y      <none>        50051/TCP, 9090/TCP
payment-service        ClusterIP   None            <none>        9090/TCP
notification-service   ClusterIP   None            <none>        9090/TCP
```

> **🧠 `CLUSTER-IP: None` 은 뭔가? (Headless Service)**
> 보통 Service 는 ClusterIP(가상 VIP)를 받고 kube-proxy 가 iptables 로 분산. Headless 는 VIP 없이 **DNS A 레코드에 모든 Pod IP** 를 직접 반환.
> 클라이언트가 직접 Pod 을 골라 연결 → gRPC 의 클라이언트 측 로드밸런싱이나 StatefulSet(`pod-0.svc`) 에 적합.
> 본 lab의 `payment`/`notification` 은 외부 호출 받지 않고 메트릭만 노출하면 되므로 VIP 불필요 → headless.

## 3. Ingress 확인

```bash
kubectl get ingress -n order msa --watch
```

ADDRESS가 채워질 때까지 1~2분 대기:
```
NAME   CLASS   HOSTS   ADDRESS                                                     PORTS
msa    alb     *       k8s-eksstudy-xxxxxx.ap-northeast-2.elb.amazonaws.com        80
```

> **🧠 ALB Target 모드: `ip` vs `instance`**
> AWS LB Controller 는 `alb.ingress.kubernetes.io/target-type` 어노테이션으로 두 모드 중 선택:
> - **`ip`** (권장): ALB 가 Pod IP 로 직접 라우팅. NodePort 안 거침 → 한 홉 적고 hairpin 없음. VPC CNI 라 가능
> - **`instance`**: ALB → 노드의 NodePort → kube-proxy → Pod. 호환성 위주
>
> Pod IP 로 직접 가는 게 가능한 건 EKS의 VPC CNI 가 Pod 에 진짜 VPC IP 를 주기 때문 (Part 6에서 학습).

## 4. 외부 호출 테스트

```bash
ALB_DNS=$(kubectl get ingress -n order msa -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "ALB: http://$ALB_DNS"

# Frontend
curl -s http://$ALB_DNS/ | grep "EKS Study Demo"

# Order API
curl -s -X POST http://$ALB_DNS/api/orders \
  -H 'Content-Type: application/json' \
  -d '{"user_id":"u1","amount":1500}' | jq

# 같은 ID 로 GET
ID=$(curl -s -X POST http://$ALB_DNS/api/orders \
  -H 'Content-Type: application/json' \
  -d '{"user_id":"u1","amount":2000}' | jq -r .id)
curl -s http://$ALB_DNS/api/orders/$ID | jq
```

## 5. 클러스터 내부 통신 (gRPC) 확인

```bash
kubectl run -it --rm grpc-test --image=fullstorydev/grpcurl:v1.9.0-buster \
  -n order \
  --command -- /bin/grpcurl -plaintext \
  -d '{"name":"finn","email":"f@x.io"}' \
  user-service:50051 user.v1.UserService/CreateUser
```

기대: `id`, `name`, `email` 이 들어있는 JSON.

> **🧠 K8s 의 서비스 디스커버리: `user-service:50051` 가 어떻게 풀리나**
> 같은 NS 의 Pod 은 그냥 `user-service` 만으로 DNS 해석 가능 (CoreDNS 가 `user-service.order.svc.cluster.local` 로 자동 확장).
> 다른 NS 면 `user-service.other-ns` 로 명시. 환경변수도 자동으로 주입되지만(`USER_SERVICE_SERVICE_HOST`) Pod 시작 시점 변수라 권장 X.

## 6. ServiceMonitor 검증 (Part 8 monitoring 이 떠 있다고 가정)

```bash
kubectl apply -f /tmp/msa/base/servicemonitor.yaml

# Prometheus 에서 target 확인
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090 &

# 브라우저 http://localhost:9090/targets 에서 "order-msa" 검색
# 또는 CLI
sleep 30
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="order-msa")'
```

> **🧠 ServiceMonitor 가 NS 를 가로지를 수 있는 이유**
> Prometheus 객체에 `serviceMonitorNamespaceSelector` 가 비어있으면 (또는 `{}` 이면) 모든 NS 의 SM 을 본다는 뜻.
> 그래서 `monitoring` NS 의 Prometheus 가 `order` NS 의 Service 를 scrape 가능.
>
> 단, ServiceMonitor 자체에는 여전히 `release: kps` 라벨이 필요 (Part 8 lab-02 에서 다룬 selector). 라벨 없으면 무시됨.

## 7. 메트릭 쿼리

```bash
# 메트릭 데이터 들어오나?
curl -sG http://localhost:9090/api/v1/query \
  --data-urlencode 'query=up{namespace="order"}' | jq '.data.result'
```

기대: 모든 서비스의 `up=1` (notification-service는 healthz 가 200 이라 up=1 일 수도, 실제 로직은 Kafka 안 붙어 다운).

## 학습 확인 질문

1. notification-service 의 CrashLoopBackOff 가 정상인 이유는?
2. order-service 가 user-service 를 호출할 때 사용하는 DNS 이름은?
3. ALB 의 Target Group 에 등록된 Pod IP 는 어떤 NS 의 Pod 인가?

다음: [lab-03-end-to-end.md](./lab-03-end-to-end.md)
