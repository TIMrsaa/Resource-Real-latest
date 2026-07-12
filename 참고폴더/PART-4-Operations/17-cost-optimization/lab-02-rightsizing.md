# Lab 02 — Right-Sizing (Container Insights + VPA)

> **🌱 핵심 개념 미리보기**
> - **Right-sizing**: requests/limits 를 실측 사용량 기준으로 조정 = "남는 자원 = 낭비된 돈" 이슈 해결.
> - **VPA (Vertical Pod Autoscaler)**: Pod 의 CPU/메모리 requests 를 추천/자동 변경. 수직 스케일.
> - **VPA 의 3가지 모드**: `Off` (추천만), `Initial` (생성 시 1회), `Auto` (재시작하며 패치).
> - **Container Insights**: CloudWatch 가 EKS Pod 의 CPU/메모리/네트워크 메트릭을 수집해 Pod 별 사용률 제공.
> - **HPA vs VPA 충돌**: 둘 다 CPU 를 보면 무한 루프 위험 → VPA 는 메모리만, HPA 는 CPU 로 분리하는 패턴.

## 1. 사용률 분석 (Container Insights / Prometheus)

### Prometheus 쿼리들

CPU 사용률 vs requests:
```
sum(rate(container_cpu_usage_seconds_total{namespace="order"}[5m])) by (pod, container)
  / sum(kube_pod_container_resource_requests{namespace="order",resource="cpu"}) by (pod, container)
```

기대: 0.0 ~ 1.0+ 의 비율. **0.5 미만이면 over-provisioning**.

> **🧠 왜 100% 가 아니라 50~70% 가 이상적인가**
> requests = 100% 사용률이면 부하 스파이크에 즉시 throttle/OOM. 헤드룸이 0.
> 반대로 10% 면 90% 의 자원이 노드에서 점유만 차지하고 다른 Pod 가 못 들어옴.
> 일반 권고: **CPU 50~70%, 메모리 60~80%**. 메모리는 OOMKill 위험이 더 크니 헤드룸 더 크게.

### Container Insights (CloudWatch)

메모리:
```
sum(container_memory_working_set_bytes{namespace="order"}) by (pod, container)
  / sum(kube_pod_container_resource_requests{namespace="order",resource="memory"}) by (pod, container)
```

### Container Insights (CloudWatch)

CloudWatch → Container Insights → Resources → Performance.
- Pod 별 CPU / Memory utilization
- 여러 시점의 평균 / max 비교

## 2. VPA 설치 (학습용 — 추천 모드)

```bash
git clone --depth=1 https://github.com/kubernetes/autoscaler.git /tmp/autoscaler
cd /tmp/autoscaler/vertical-pod-autoscaler

./hack/vpa-up.sh
kubectl get pods -n kube-system -l app=vpa-recommender
```

또는 Helm:
```bash
helm repo add fairwinds https://charts.fairwinds.com/stable
helm install vpa fairwinds/vpa -n vpa --create-namespace
```

## 3. VPA 적용 (order-service 대상)

```bash
cat > /tmp/vpa.yaml <<'EOF'
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: order-service
  namespace: order
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: order-service
  updatePolicy:
    updateMode: "Off"     # 추천만
  resourcePolicy:
    containerPolicies:
      - containerName: '*'
        controlledResources: ["cpu", "memory"]
        minAllowed: { cpu: 50m, memory: 64Mi }
        maxAllowed: { cpu: 1, memory: 1Gi }
EOF
kubectl apply -f /tmp/vpa.yaml
```

> **🧠 VPA 의 3 컴포넌트가 하는 일**
> - **Recommender**: Prometheus/metrics-server 의 사용량 히스토그램(8일 슬라이딩 윈도우)을 보고 Target/Lower/Upper 추천.
> - **Updater**: `Auto` 모드에서 추천이 현재값과 크게 다르면 Pod evict (재시작 트리거).
> - **Admission Controller**: 새 Pod 생성 시 mutating webhook 으로 requests 패치.
>
> `updateMode: "Off"` 면 Recommender 만 동작 — 안전하게 추천만 보고 사람이 수동 적용.

## 4. 부하 발생 + 데이터 수집 (15~30분)

```bash
# Module 14 의 부하 발생기 활용 — JSON --overrides 의 quote 깨짐 방지를 위해 매니페스트로 분리
ALB_DNS=$(kubectl get ingress -n order msa -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: loadgen
  namespace: order
spec:
  restartPolicy: Always
  containers:
    - name: loadgen
      image: alpine:3.19
      command: ["sh","-c"]
      args:
        - |
          apk add -q curl
          while true; do
            curl -s -X POST http://${ALB_DNS}/api/orders \\
              -H 'Content-Type: application/json' \\
              -d '{"user_id":"u1","amount":1}' > /dev/null
            sleep 0.1
          done
EOF

sleep 1200    # 20분 데이터 수집
```

## 5. VPA 추천 확인

```bash
kubectl describe vpa -n order order-service
```

기대 (`Status` 섹션):
```
Status:
  Recommendation:
    Container Recommendations:
      Container Name:  app
      Lower Bound:
        Cpu:     20m
        Memory:  50Mi
      Target:                  ← 권장값
        Cpu:     85m
        Memory:  120Mi
      Upper Bound:
        Cpu:     200m
        Memory:  200Mi
```

`Target` 이 VPA 의 권장 requests. 현재 `100m / 128Mi` 와 비교:
- CPU: 100m → 85m (15% 감소 가능)
- Memory: 128Mi → 120Mi (소폭)

> **🧠 Lower / Target / Upper 의 통계적 의미**
> VPA 는 사용량 분포의 백분위수로 추천을 만듦.
> - **Lower Bound**: ~50 백분위. 이 아래로 줄이면 throttle/OOM 위험.
> - **Target**: 90 백분위 + 안전 마진. 권장값.
> - **Upper Bound**: 95 백분위. 이 이상은 명백한 over-provisioning.
>
> 데이터가 적으면 (학습용 20분 부하) bound 가 넓고 부정확. 운영에선 최소 며칠치 데이터 권장.

## 6. 적용 옵션

### 옵션 A — 수동 적용
```bash
kubectl patch deploy order-service -n order --type=merge -p '
{"spec":{"template":{"spec":{"containers":[
  {"name":"app","resources":{"requests":{"cpu":"85m","memory":"120Mi"}}}
]}}}}'
```

### 옵션 B — VPA Auto 모드
```bash
kubectl patch vpa order-service -n order --type=merge -p '{"spec":{"updatePolicy":{"updateMode":"Auto"}}}'
```

→ VPA 가 Pod 재시작하며 자동 패치. 운영에서는 신중하게 (Pod 재시작 주의).

> **🧠 Auto 모드의 위험**
> VPA 는 in-place resize 가 아니라 **Pod 를 evict 후 재생성**으로 새 requests 적용 (1.27 부터 in-place resize 알파, 1.33 GA 진행 중).
> = 단일 Replica Deployment 면 재시작 동안 다운타임. PDB 가 막으면 무한 대기.
> 운영 권장: replicas ≥ 2 + PDB(`maxUnavailable: 1`) + 점검 시간대 schedule.

## 7. HPA 와 충돌 회피

HPA 가 같은 Pod 의 CPU 로 수평 스케일 + VPA 가 CPU requests 로 수직 → 충돌.

**해결책**:
- VPA 는 Memory 만, HPA 는 CPU
- 또는 VPA 의 `updateMode: Off` 로 추천만, 사람이 검토 후 적용

## 8. 정리

```bash
kubectl delete pod -n order loadgen
kubectl delete vpa -n order order-service
```

## 학습 확인

- Right-sizing 의 목표 utilization 비율은 (이상적)?
- VPA Auto 모드의 위험은?
- HPA + VPA 같이 쓰는 패턴은?

다음: [lab-03-opencost.md](./lab-03-opencost.md)
