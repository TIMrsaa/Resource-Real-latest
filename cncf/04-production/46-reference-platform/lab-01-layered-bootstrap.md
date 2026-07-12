# Lab 01 — 층별 부트스트랩과 의존 순서

> 축소판 레퍼런스 플랫폼을 kind에 **층 순서대로** 올려, 각 층이 아래 층에 어떻게 의존하는지, 순서를 틀리면 무엇이 막히는지 체감합니다. 도구 하나하나는 이미 배웠으니, 여기선 **순서와 의존**에 집중합니다.

## 0. 준비 — 클러스터 기반 (층 1)

```bash
kind create cluster --name platform
# kind는 이미 K8s + CNI(kindnet) + CoreDNS + containerd 포함 (층 1 완성)
kubectl get pods -n kube-system
# coredns, kindnet, etcd, kube-* ... (기반 층)
```

층 1(클러스터 기반)은 kind가 제공합니다. 실제로는 26(CNI 선택)·20(CoreDNS)이 여기 들어갑니다.

## 1. 층 2 — GitOps 뼈대 (ArgoCD)

```bash
# ArgoCD 설치 (나머지 층을 배포할 뼈대)
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl -n argocd wait deploy/argocd-server --for=condition=Available --timeout=300s
```

**왜 GitOps를 먼저?** — 이후 모든 층을 ArgoCD Application으로 선언할 것이기 때문입니다(app-of-apps). GitOps가 조립의 뼈대입니다(theory 4절).

## 2. 층 3 — cert-manager (많은 것의 전제)

```bash
# cert-manager를 먼저 (웹훅 TLS·인증서의 전제)
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true

kubectl -n cert-manager wait deploy --all --for=condition=Available --timeout=180s
```

**왜 일찍?** — 뒤에 올 메시(mTLS)·인그레스(TLS)·많은 웹훅이 cert-manager에 의존합니다. 나중에 깔면 그것들이 막힙니다(19). 순서 실험:

```bash
# cert-manager가 만드는 Issuer로 자체 서명 CA 준비 (내부 인증서용)
cat <<'EOF' | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: { name: selfsigned }
spec:
  selfSigned: {}
EOF
kubectl get clusterissuer selfsigned
# READY True → 이제 다른 층이 인증서를 요청할 수 있습니다
```

## 3. 층 4 — 관측 (일찍!)

```bash
# kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.enabled=true \
  --set prometheus.prometheusSpec.resources.requests.memory=400Mi

kubectl -n monitoring wait deploy --all --for=condition=Available --timeout=300s 2>/dev/null || true
kubectl -n monitoring get pods
# prometheus, grafana, kube-state-metrics, node-exporter ...
```

**왜 관측을 일찍?** — 이제부터 층을 더 쌓을 때, 무언가 안 되면 관측 층에서 봐야 합니다. 관측 없이 복잡한 것을 도입하면 "눈 감고 운전"입니다(theory 3절). 확인:

```bash
# Prometheus가 이미 클러스터·자기 아래 층들을 관측 중
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090 &
# http://localhost:9090 → Targets에 kube-system·cert-manager 등이 이미 수집됨
```

## 4. 층 5 — 정책 가드레일 (Kyverno)

```bash
# Kyverno (배포 시 검증 — 앱 전에 가드레일)
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install kyverno kyverno/kyverno --namespace kyverno --create-namespace

kubectl -n kyverno wait deploy --all --for=condition=Available --timeout=180s 2>/dev/null || true

# 간단한 가드레일: latest 태그 금지 (32의 정책)
cat <<'EOF' | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: disallow-latest-tag }
spec:
  rules:
    - name: require-image-tag
      match: { any: [{ resources: { kinds: [Pod] } }] }
      validate:
        failureAction: Audit
        message: "latest 태그 금지"
        pattern:
          spec:
            containers:
              - image: "!*:latest"
EOF
```

**왜 앱 전에?** — 정책이 앱보다 먼저 있어야 앱 배포 시점에 검증(admission)이 작동합니다(32). 나중에 깔면 이미 들어온 위반을 못 막습니다.

## 5. 의존 순서 확인 — 틀리면 어떻게 되나

```
지금까지 순서: 기반 → GitOps → cert-manager → 관측 → 정책

만약 순서를 뒤집었다면?
  - 관측을 마지막에 → 앞 층들 도입 시 문제를 못 봄 (디버그 불가)
  - cert-manager를 나중에 → 웹훅 있는 것들(Kyverno도!) TLS 막힘
  - 정책을 앱 뒤에 → 이미 배포된 위반을 못 잡음

★ 각 층의 위치는 의존이 정합니다 (theory 3절)
```

```bash
# 실제로 Kyverno도 cert-manager 없이(또는 자체 인증서 없이) 웹훅 TLS가 필요했습니다
# → cert-manager를 먼저 깐 것이 옳았습니다 (또는 Kyverno 자체 인증서 관리)
kubectl get validatingwebhookconfiguration | grep -E "kyverno|cert-manager"
# 웹훅들이 TLS로 API 서버와 통신 → 인증서 인프라가 전제
```

## 6. 정리

```bash
# 개별 정리는 cleanup.sh (helm uninstall + kind delete)
pkill -f "port-forward" 2>/dev/null || true
```

## 정리

- 층 순서: 기반(K8s·CNI·DNS) → GitOps → cert-manager → 관측 → 정책 → (메시·앱)
- **cert-manager는 일찍** — 웹훅·mTLS·인증서의 전제 (뒤 층이 의존)
- **관측은 일찍** — 안 보이면 뒤 층 도입 시 디버그 불가
- **정책은 앱 전에** — admission이 배포 시점에 작동하려면
- **★ 각 층의 위치는 의존이 강제합니다 — 순서를 틀리면 닭-달걀·디버그 불가**
