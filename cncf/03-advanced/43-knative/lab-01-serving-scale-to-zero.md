# Lab 01 — Knative Serving: scale-to-zero와 리비전·트래픽

> Knative를 kind에 설치하고, Service를 배포하고, scale-to-zero(0→1 콜드 스타트, N→0)를 직접 관찰하고, 리비전·트래픽 분할로 카나리를 해봅니다.

## 0. 준비 — Knative quickstart

```bash
# kind + Knative를 한 번에 (knative quickstart 플러그인)
# 방법 A: quickstart (kind + Knative Serving/Eventing + Kourier)
kn quickstart kind
# → kind 클러스터 'knative' 생성 + Knative Serving/Eventing 설치

# 방법 B가 필요하면 수동 설치(공식 YAML)도 가능하나 quickstart 권장
kubectl get pods -n knative-serving
# activator, autoscaler, controller, webhook ... Running
```

```bash
# Knative Service의 CRD 확인
kubectl get crd | grep knative
# services.serving.knative.dev
# revisions.serving.knative.dev
# routes / configurations ...
# brokers / triggers (eventing) ...
```

## 1. 첫 Knative Service 배포

```yaml
# hello.yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: hello
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/target: "10"   # Pod당 동시성 목표 10
    spec:
      containers:
        - image: ghcr.io/knative/helloworld-go:latest
          env:
            - name: TARGET
              value: "Knative"
```

```bash
kubectl apply -f hello.yaml

# 배포되면서 Revision·Route가 자동 생성
kubectl get ksvc hello
# NAME    URL                                  READY
# hello   http://hello.default.127.0.0.1.sslip.io   True

kubectl get revision       # hello-00001 (첫 리비전)
kubectl get route hello    # 트래픽 라우팅
```

**관찰** — Service 하나로 Deployment+Service+HPA+Ingress+Revision이 다 생겼습니다. 이것이 서버리스 추상입니다.

## 2. scale-to-zero 관찰 — N→0

```bash
# 배포 직후엔 Pod가 있다가, 요청 없으면 ~60초 후 0으로
kubectl get pod -l serving.knative.dev/service=hello -w
# hello-00001-deployment-xxx   Running
# ... (60초 요청 없음) ...
# hello-00001-deployment-xxx   Terminating
# (Pod 0개)

kubectl get pod -l serving.knative.dev/service=hello
# No resources found   ← scale-to-zero 완료!
```

**핵심** — 요청이 없자 Pod가 완전히 0이 됐습니다. HPA(08)는 못 하는 것입니다. 이 상태에서 비용(CPU·메모리)이 0입니다.

## 3. 0→1 콜드 스타트 관찰

```bash
# Pod 0인 상태에서 요청 → Activator가 붙잡고 Pod를 띄움
URL=$(kubectl get ksvc hello -o jsonpath='{.status.url}')

# 첫 요청 (콜드 스타트 — 약간 느림)
time curl $URL
# Hello Knative!
# real  0m2.3s   ← 콜드 스타트 (Pod 뜨는 시간 포함)

# 두 번째 요청 (Pod 이미 떠 있음 — 빠름)
time curl $URL
# Hello Knative!
# real  0m0.05s  ← 웜 (직접 전달)

# Pod가 다시 떴습니다
kubectl get pod -l serving.knative.dev/service=hello
# hello-00001-deployment-xxx   Running
```

**관찰** — 첫 요청은 느리고(콜드 스타트, Activator가 Pod를 띄우고 기다림), 이후는 빠릅니다. 이 콜드 스타트 지연이 서버리스의 대가입니다(pitfalls에서 완화법). Activator 로그로 확인:

```bash
kubectl logs -n knative-serving -l app=activator --tail=20
# 요청을 버퍼링하고 Pod 준비를 기다린 흔적
```

## 4. 리비전과 트래픽 분할 (카나리)

```bash
# 새 버전 배포 (TARGET 변경) → 새 Revision 생성
kubectl patch ksvc hello --type merge -p \
  '{"spec":{"template":{"metadata":{"name":"hello-00002"},"spec":{"containers":[{"image":"ghcr.io/knative/helloworld-go:latest","env":[{"name":"TARGET","value":"Knative-v2"}]}]}}}}'

kubectl get revision
# hello-00001   (옛 버전)
# hello-00002   (새 버전)
```

```yaml
# traffic.yaml — 90/10 카나리
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: hello
spec:
  template:
    metadata:
      name: hello-00002
    spec:
      containers:
        - image: ghcr.io/knative/helloworld-go:latest
          env: [{ name: TARGET, value: "Knative-v2" }]
  traffic:
    - revisionName: hello-00001
      percent: 90                  # 옛 버전 90%
    - revisionName: hello-00002
      percent: 10                  # 새 버전 10% (카나리)
```

```bash
kubectl apply -f traffic.yaml

# 여러 번 요청하면 ~10%가 v2
for i in $(seq 1 20); do curl -s $URL; echo; done | sort | uniq -c
#  18 Hello Knative!       ← v1 (90%)
#   2 Hello Knative-v2!    ← v2 (10%)
```

**관찰** — 08의 카나리를 YAML `percent`만으로 했습니다. 문제 없으면 10→50→100으로 올리고, 문제 생기면 0으로(즉시 롤백, 옛 리비전이 남아 있으므로). 24(메시)의 트래픽 분할과 같은 효과지만 Knative에 내장입니다.

## 5. 정리

```bash
kubectl delete -f hello.yaml 2>/dev/null || true
# 클러스터는 cleanup.sh
```

## 정리

- Knative Service 하나 = Deployment+Service+HPA+Ingress+Revision (서버리스 추상)
- **scale-to-zero**: 요청 없으면 Pod 0 (HPA 불가), 요청 오면 Activator가 0→1
- **콜드 스타트**: 첫 요청은 Pod 뜨는 시간만큼 지연 (서버리스의 대가)
- **리비전·트래픽**: 불변 Revision + `percent`로 카나리·즉시 롤백(08 내장)
- **★ Activator+KPA가 scale-to-zero의 핵심 — 0을 가능케 하되 콜드 스타트를 낳습니다**
