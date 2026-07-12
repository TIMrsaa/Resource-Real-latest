# Lab 03 — E2E 트래픽 + 모니터링

## 학습 확인 포인트

- [ ] 부하 발생기를 클러스터 안에서 돌려 봄
- [ ] Grafana 대시보드에서 RPS / 에러율 / latency 확인
- [ ] 로그를 stern 으로 다중 Pod 동시 tail

> **🌱 핵심 개념 미리보기**
> - **부하 발생기 (loadgen)**: 클러스터 내부 Pod 에서 ALB 로 요청을 반복 → 실 트래픽 흉내. JMeter/k6 의 단순 버전
> - **Container Insights**: AWS 가 만든 EKS 모니터링 addon. `fluent-bit` 가 노드에서 모든 컨테이너 stdout 을 CloudWatch Logs 로 송출
> - **PromQL `rate()`**: Counter 메트릭의 초당 변화율. RPS, CPU 사용률 계산의 기본 도구
> - **stern**: kubectl logs 의 멀티 Pod 버전. 라벨/패턴으로 여러 Pod 의 로그를 동시에 색깔로 구분해 tail
> - **하이브리드 관측**: Prometheus(메트릭) + CloudWatch Logs(로그) 를 병행 → 메트릭으로 이상 감지, 로그로 원인 분석

## 1. 부하 발생기 배포

```bash
ALB_DNS=$(kubectl get ingress -n order msa -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# kubectl run --overrides 의 JSON quote/escape 가 bash 에서 깨지기 쉬워 매니페스트로 분리
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
              -d '{"user_id":"u1","amount":100}' > /dev/null
            sleep 0.1
          done
EOF
```

→ 약 10 RPS.

> **🧠 왜 매니페스트 파일로 분리했나? (`kubectl run` 의 한계)**
> `kubectl run --image=alpine --command -- sh -c "..."` 형태로 시작하면 bash quoting/escape 가 다층 중첩 → JSON 변환 시 백슬래시가 깨지기 일쑤.
> heredoc + `kubectl apply -f -` 패턴이 가장 안전: 셸이 한 번만 변수 치환(`${ALB_DNS}`)하고, 매니페스트는 원본 그대로 K8s API 로 전달.
>
> 운영 부하 테스트는 `k6`/`Locust`/`Vegeta` Pod 를 권장. curl 루프는 RPS 정밀도와 분포가 부정확.

## 2. 메트릭 관찰 (Prometheus)

별도 터미널:
```bash
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-prometheus 9090:9090
```

브라우저: http://localhost:9090/graph

쿼리 예시:
```
# order-service Pod 의 CPU 사용률
sum(rate(container_cpu_usage_seconds_total{namespace="order",pod=~"order-service.*"}[1m])) by (pod)

# 메모리
sum(container_memory_working_set_bytes{namespace="order",pod=~"order-service.*"}) by (pod)

# 메트릭 endpoint up 상태
up{namespace="order"}
```

> **🧠 `container_cpu_usage_seconds_total` 이 어디서 나왔나?**
> kubelet 안에 통합된 **cAdvisor** 가 노출하는 메트릭. 컨테이너 런타임에서 cgroup 통계를 읽어 Counter 형태(누적 CPU 초)로 노출.
> Counter 라 그대로 보면 단조 증가만 보임 → `rate(...[1m])` 으로 초당 사용량(즉, vCPU 사용률) 으로 변환해야 의미 있음.
>
> kube-prometheus-stack 의 ServiceMonitor 가 자동으로 kubelet `/metrics/cadvisor` 를 scrape 하기 때문에 우리가 따로 설정 안 해도 잡힘.

## 3. Grafana 대시보드

```bash
kubectl port-forward -n monitoring svc/kps-grafana 3000:80
```

http://localhost:3000 (admin / eks-study-admin).

좌측 → Dashboards → Browse → "Kubernetes / Compute Resources / Namespace (Pods)"
- Namespace: `order`
- 시각: 지난 30분
- Pod 별 CPU / Memory 시각화

## 4. 로그 확인 (stern)

```bash
stern -n order --tail 5 .                 # 모든 Pod
stern -n order order-service              # 특정 패턴
stern -n order -l app.kubernetes.io/name=order-service --since 5m
```

기대: `loadgen` 의 요청이 `order-service` 의 요청 처리 로그로 흐름.

> **🧠 stern 이 kubectl logs 보다 좋은 점**
> `kubectl logs` 는 한 Pod 만 가능 → Deployment 의 모든 replica 보려면 셸 루프 필요.
> stern 은 라벨/이름 패턴으로 여러 Pod 동시 tail + Pod 별 색상 구분 + 새로 뜨는 Pod 자동 follow.
> 즉, 롤링 업데이트 중에도 끊김 없이 따라감. 디버깅 필수 도구.

## 5. 부하 종료

```bash
kubectl delete pod loadgen -n order
```

## 6. CloudWatch 로그도 동시에 보내짐 확인

```bash
aws logs tail /aws/containerinsights/eks-study/application \
  --since 5m \
  --filter-pattern '"order-service"' | head -10
```

→ 같은 로그가 CloudWatch Logs 에도 있음 (Container Insights addon 이 설치되어 있다면).

> **🧠 왜 같은 로그가 두 군데에 있나?**
> Container Insights 가 설치되면 `aws-for-fluent-bit` DaemonSet 이 노드의 `/var/log/containers/*.log` 파일을 읽어 CloudWatch Logs 로 전송 (`/aws/containerinsights/<cluster>/application` 등 그룹).
> 컨테이너 stdout/stderr 는 어차피 노드 디스크 파일로 남으므로, fluent-bit 가 그 파일을 tail 하는 구조. 앱은 아무것도 몰라도 됨.
>
> CloudWatch Logs 비용은 **수집(ingest) 기준 GB 단가** 가 가장 큼. 운영에선 fluent-bit 필터로 디버그 로그 드롭하거나 retention 짧게 설정해 비용 관리.

## 7. 회고

이 시점까지 같은 워크로드의 메트릭/로그를:
- **Prometheus** (PromQL 로 쿼리, Grafana 시각화)
- **CloudWatch Logs** (필터 검색)

에서 동시 확인 가능 → **하이브리드 관측 스택** 완성.

## 학습 확인 질문

1. 같은 로그가 Prometheus 에서도 보일까? 안 보인다면 어떤 도구를 추가해야 하나?
2. Grafana 대시보드에서 가장 빠르게 "어떤 Pod가 CPU를 가장 많이 쓰는가?" 를 보려면?
3. 부하가 늘어 Pod이 자동 스케일되게 하려면 무엇을 추가해야 하나?

다음: [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`
