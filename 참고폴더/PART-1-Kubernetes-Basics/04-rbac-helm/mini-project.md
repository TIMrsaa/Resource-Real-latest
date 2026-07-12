# Part 1 미니 프로젝트 — order-service 단독 배포

## 목표

지금까지 배운 모든 개념을 통합:

- Helm 차트로 패키징된 `order-service` 를 **최소 EKS 클러스터에 배포**
- `Service` 로 내부 노출 + `port-forward` 로 외부 접근 (LB 비용 절감)
- ConfigMap으로 환경변수 주입
- ServiceAccount + RoleBinding (자기 자신의 정보만 조회 가능)
- HPA 활성화 후 부하 발생 → Pod 늘어나는 것 확인

## 산출물

- 배포된 order-service Pod 2~10개
- HPA 동작으로 Pod 수가 부하에 반응
- `kubectl logs` 로 요청 로그 확인 가능
- 정리 후 잔존 리소스 0

> **🌱 핵심 개념 미리보기**
> - **통합 학습**: Part 1 의 Pod, Deployment, Service, ConfigMap, RBAC, Helm, HPA 가 한번에 등장하는 졸업 과제.
> - **HPA (Horizontal Pod Autoscaler)**: CPU/메모리 메트릭 기반 Pod 수 자동 조절.
> - **metrics-server**: HPA가 Pod 메트릭 가져오는 소스. EKS 에 기본 미설치 → 직접 설치 필요.
> - **port-forward**: LB 비용 안 쓰고 로컬에서 테스트할 때 쓰는 트릭. 임시용.
> - **부하 테스트 → 자동 스케일링**: 가장 시각적으로 K8s 의 자동화 매력을 보여주는 시나리오.

---

## 1. 사전 준비 점검

```bash
# 클러스터
kubectl get nodes
kubectl get csidrivers ebs.csi.aws.com

# metrics-server (HPA에 필수)
kubectl get deploy -n kube-system metrics-server
```

`metrics-server` 가 없으면 설치:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl wait --for=condition=available --timeout=60s deploy/metrics-server -n kube-system
```

> **🧠 metrics-server 가 왜 필요한가**
> HPA는 `kubectl top pods` 가 보여주는 CPU/메모리 값을 기반으로 동작. 이 값을 채우는 게 metrics-server.
> 없으면 HPA가 `<unknown>/50%` 로 표시되고 스케일링 작동 X.
> EKS는 기본 미설치 (구글 GKE 와 차이) → 직접 설치 필요. 운영에선 보통 helm 또는 EKS addon 으로.

EKS의 일부 환경에서는 metrics-server의 `--kubelet-insecure-tls` 플래그가 필요할 수 있음:
```bash
kubectl patch deploy metrics-server -n kube-system --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}
]'
```

## 2. 이미지 빌드 + ECR 푸시

```bash
cd "$(git rev-parse --show-toplevel)"
bash 00-prerequisites/scripts/ecr-push-all.sh
```

확인:
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2
aws ecr describe-images \
  --repository-name eks-study/order-service \
  --query 'imageDetails[].imageTags[]' --output text
```

## 3. values 파일 만들기

```bash
cd PART-1-Kubernetes-Basics/04-rbac-helm
cat > values-prod.yaml <<EOF
replicaCount: 2

image:
  repository: ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/eks-study/order-service
  tag: latest

env:
  PORT: "8080"
  LOG_LEVEL: info

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 8
  targetCPUUtilizationPercentage: 50
EOF
```

## 4. Helm 설치

```bash
helm install order-service ./charts/order-service \
  -f values-prod.yaml \
  --namespace order --create-namespace

helm list -n order
kubectl get all -n order
```

## 5. 동작 검증

### 헬스체크
```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=order-service -n order --timeout=120s
kubectl port-forward svc/order-service -n order 8080:80 &
PF_PID=$!

curl -s http://localhost:8080/healthz -w "\n%{http_code}\n"
```

기대: `200`.

> **🧠 port-forward 의 작동 방식**
> 로컬 포트 → kubectl → API Server → kubelet → 대상 Pod (또는 Service의 backend Pod 1개) 로 터널링.
> 즉 진짜 LB가 아니라 **단일 Pod로 가는 1:1 프록시**. 부하 테스트엔 부적합 (한 Pod에만 트래픽).
> 학습/디버깅용. 운영 노출은 Ingress 또는 LoadBalancer 사용.

### POST /orders + GET /orders/:id
```bash
RESP=$(curl -s -X POST http://localhost:8080/orders \
  -H 'Content-Type: application/json' \
  -d '{"user_id":"u1","amount":1000}')
echo "$RESP"

ID=$(echo $RESP | jq -r '.id')
curl -s http://localhost:8080/orders/$ID
```

기대: 생성된 ID로 GET 시 동일한 주문 정보 반환.

## 6. 부하 발생 + HPA 동작 관찰

별도 터미널 1: HPA 와 Pod 수 watch
```bash
watch -n2 'kubectl get hpa,pods -n order'
```

별도 터미널 2: 부하 발생기
```bash
kubectl run -it --rm load \
  --image=alpine \
  -n order \
  --restart=Never \
  -- sh -c 'apk add -q curl && while true; do
    curl -s -X POST http://order-service/orders \
      -H "Content-Type: application/json" \
      -d "{\"user_id\":\"u1\",\"amount\":100}" > /dev/null
  done'
```

watch 화면에서 본 흐름:
```
HPA  TARGETS    MINPODS  MAXPODS  REPLICAS
...   45%/50%   2        8        2

→ 시간이 흐르며:
...   80%/50%   2        8        2     ← target 초과
...   80%/50%   2        8        4     ← Pod 증가
...   60%/50%   2        8        6
```

5~10분 정도 반응 시간 (HPA는 1분 단위 평가).

> **🧠 HPA가 즉시 반응하지 않는 이유**
> 1. metrics-server가 메트릭 수집하는 데 ~15초.
> 2. HPA controller 가 기본 15초마다 평가.
> 3. 새 Pod 만들어져 Ready 되기까지 (이미지 pull + readiness) ~30초~수분.
> 4. scale-up 결정에 1~3분, scale-down 은 안정성 위해 기본 5분 안정화 윈도우.
> = 부하 급증 즉시 대응 어려움 → 운영에선 buffer replica 두거나 KEDA 같은 더 빠른 스케일러 고려.

## 7. 부하 종료 후 축소 관찰

부하 컨테이너 Ctrl+C 종료 → 5~10분 후:
```
...   30%/50%   2        8        4
...   15%/50%   2        8        2     ← min 으로 축소
```

scale down은 scale up 보다 보수적 (기본 5분 stabilization window).

## 8. 정리 (반드시!)

```bash
kill $PF_PID 2>/dev/null
helm uninstall order-service -n order
kubectl delete ns order
rm -f values-prod.yaml
```

## 9. 회고 질문

- Pod이 늘어나는 데 시간이 왜 그렇게 걸렸나? (스케줄링, 이미지 pull, readinessProbe)
- HPA 의 `targetCPUUtilizationPercentage: 50` 을 70으로 올리면 어떻게 동작이 변할까?
- Helm 차트의 어느 부분을 수정하면 ConfigMap 도 같이 배포되도록 할 수 있을까?

## Part 1 종료

축하합니다 🎉 — Part 1을 마쳤습니다.

다음 Part 2는 EKS 운영 본격: VPC CNI, ALB Controller, IRSA, 관측 스택 설치.

```bash
# Part 1 학습이 모두 끝났다면 클러스터를 삭제해 비용을 멈추세요:
eksctl delete cluster --name eks-study --region ap-northeast-2
```
