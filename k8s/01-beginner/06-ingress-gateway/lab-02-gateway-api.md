# Lab 02 — Gateway API: 표준 필드로 카나리/헤더 라우팅

> lab-01과 같은 요구사항(경로 라우팅 + 90:10 카나리)을 Gateway API 표준 필드만으로 구현하고, 헤더 라우팅까지 얹습니다.
> 백엔드(store-v1/v2)는 lab-01에서 배포한 것을 그대로 사용.

## Step 1. Gateway API CRD + NGINX Gateway Fabric 설치

```bash
# ① 표준 CRD (Gateway API는 코어가 아니라 CRD로 배포됩니다)
kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v2.1.0" | kubectl apply -f -

# ② 구현체 (NGINX Gateway Fabric)
helm upgrade --install ngf oci://ghcr.io/nginx/charts/nginx-gateway-fabric \
  --namespace nginx-gateway --create-namespace

kubectl get gatewayclass
```

예상 출력:
```
NAME    CONTROLLER                                   ACCEPTED
nginx   gateway.nginx.org/nginx-gateway-controller   True       ← 구현체가 등록됨
```

> 💡 버전 확인: 설치 전 https://github.com/nginx/nginx-gateway-fabric/releases 에서 최신 태그로 `ref=`를 갱신하세요.

## Step 2. Gateway + HTTPRoute 적용

```bash
kubectl apply -f manifests/gateway-routes.yaml
kubectl get gateway main-gw
```

예상 출력 (~2분 후):
```
NAME      CLASS   ADDRESS                          PROGRAMMED
main-gw   nginx   xxxx.elb.ap-northeast-2....      True         ← LB 생성 + 규칙 적용 완료
```

```bash
# Route가 Gateway에 정상으로 붙었는지 (조건 확인 — Gateway API의 우수한 상태 보고)
kubectl describe httproute store-route | grep -A 6 "Conditions"
```

예상:
```
Conditions:
  Type:    Accepted
  Status:  True
  Type:    ResolvedRefs
  Status:  True          ← 백엔드 Service를 다 찾았다는 뜻
```

## Step 3. 가중치 카나리 검증 (표준 필드!)

```bash
GW=$(kubectl get gateway main-gw -o jsonpath='{.status.addresses[0].value}')
sleep 60   # DNS 전파
for i in $(seq 1 100); do curl -s http://$GW/hostname; echo; done | sort | uniq -c
```

예상 출력:
```
  ~90 store-v1-...
  ~10 store-v2-...
```

✅ lab-01의 annotation 2개 + Ingress 2개 대신, **HTTPRoute 하나의 `weight` 필드**로 끝났습니다. `kubectl explain httproute.spec.rules.backendRefs.weight` 로 문서까지 나옵니다 — annotation과의 결정적 차이.

## Step 4. 헤더 라우팅 검증

```bash
curl -s http://$GW/hostname; echo                          # 일반 사용자
curl -s -H "x-beta: yes" http://$GW/hostname; echo         # 베타 사용자
curl -s -H "x-beta: yes" http://$GW/hostname; echo
```

예상 출력:
```
store-v1-... (또는 10% 확률 v2)    ← 일반: 90:10
store-v2-...                       ← 베타 헤더: 항상 v2
store-v2-...
```

✅ "베타 테스터에게만 신버전" — 실무 카나리/A‑B의 기본기가 표준 문법으로 완성.

## Step 5. 역할 분리 실감하기

```bash
kubectl get gateway,httproute
```

상상해보세요: Gateway는 플랫폼팀 리포지토리에, HTTPRoute는 각 서비스팀 리포지토리에 있습니다. 개발팀은 LB/TLS 설정을 건드릴 권한 없이 자기 라우팅만 PR 합니다. `allowedRoutes`로 "누가 내 Gateway에 붙을 수 있는지"까지 통제 — Ingress에는 불가능했던 운영 모델입니다.

## 트러블슈팅

| 증상 | 원인/해결 |
|------|----------|
| GatewayClass ACCEPTED가 False | 구현체 Pod 상태 확인: `kubectl get pods -n nginx-gateway` |
| HTTPRoute Accepted=False | parentRefs 이름/네임스페이스, Gateway의 allowedRoutes 확인 |
| ResolvedRefs=False | backendRefs의 Service 이름/포트 오타 |
| curl 타임아웃 | DNS 전파 대기, `kubectl get gateway`의 ADDRESS 재확인 |

## 정리

```bash
bash cleanup.sh
```
