# Lab 01 — Ingress 한 바퀴 (레거시 이해용)

> **목표**: Ingress의 동작과 한계를 직접 봅니다. 신규 설계에는 lab-02의 Gateway API를 쓰겠지만, 현장의 기존 클러스터를 읽으려면 필수 교양입니다.

## Step 1. 백엔드 배포

```bash
kubectl apply -f manifests/backends.yaml
kubectl get pods -l app=store
```

## Step 2. Ingress 리소스만 먼저 만들어보기 (실패 체험)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: store
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service: { name: store-v1, port: { number: 80 } }
EOF
kubectl get ingress store
```

예상 출력:
```
NAME    CLASS   HOSTS   ADDRESS   PORTS
store   nginx   *                 80        ← ADDRESS가 영원히 빈칸
```

✅ **의도된 실패**: 규칙(Ingress)만 있고 실행체(컨트롤러)가 없으니 **아무 일도 안 일어납니다.** "Ingress 만들었는데 안 돼요"의 정체.

## Step 3. ingress-nginx 컨트롤러 설치

```bash
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer
kubectl get pods,svc -n ingress-nginx
```

예상 출력 (발췌):
```
pod/ingress-nginx-controller-...   1/1   Running      ← 실행체 = nginx Pod
service/ingress-nginx-controller   LoadBalancer  ...  xxxx.elb.amazonaws.com
```

> 💡 구조 확인: 컨트롤러의 정체는 "Ingress 리소스를 watch해서 자기(nginx) 설정 파일로 변환하는 Pod + 그 앞의 LoadBalancer Service(모듈 05)"다.

## Step 4. 이제 동작 확인

```bash
kubectl get ingress store    # ADDRESS에 LB 주소가 채워짐
LB=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
sleep 60   # DNS 전파
curl -s http://$LB/hostname; echo
```

예상 출력: `store-v1-...` (v1 Pod 이름)

## Step 5. annotation 지옥 맛보기 — "카나리 10%만 v2로"

표준 Ingress 스펙에는 가중치가 없습니다. ingress-nginx 전용 annotation으로:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: store-canary
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"            # ← nginx 전용
    nginx.ingress.kubernetes.io/canary-weight: "10"       # ← nginx 전용
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service: { name: store-v2, port: { number: 80 } }
EOF

# 100번 호출해서 비율 확인
for i in $(seq 1 100); do curl -s http://$LB/hostname; echo; done | sort | uniq -c
```

예상 출력:
```
  ~90 store-v1-...
  ~10 store-v2-...
```

✅ 동작은 합니다. **그러나**: ① Ingress 리소스를 2개로 쪼개야 했고 ② annotation은 nginx 전용이라 ALB/다른 컨트롤러로 가면 전부 무효 ③ `kubectl explain`으로 문서도 못 봅니다(그냥 문자열이므로 오타도 안 잡아줌). — 이 불편함을 기억한 채 lab-02로.

## 정리 (lab-02 전에 Ingress 쪽만 철거)

```bash
kubectl delete ingress store store-canary
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete namespace ingress-nginx
# LB 삭제 확인 (모듈 05의 교훈)
kubectl get svc -A | grep LoadBalancer || echo "LB 없음 - OK"
```
