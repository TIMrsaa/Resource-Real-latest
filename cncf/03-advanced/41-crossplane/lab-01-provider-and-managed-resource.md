# Lab 01 — Provider와 Managed Resource, 조정 관찰

> Crossplane을 설치하고, Provider를 깔고, Managed Resource를 만들고, 08의 조정 루프가 인프라(여기선 실제 클라우드 대신 provider-nop의 가짜 리소스)에 어떻게 작동하는지 관찰합니다. 실제 AWS 계정 없이 개념에 집중합니다.

## 0. 준비

```bash
kind create cluster --name crossplane
```

## 1. Crossplane 설치

```bash
helm repo add crossplane-stable https://charts.crossplane.io/stable
helm repo update

kubectl create namespace crossplane-system
helm install crossplane crossplane-stable/crossplane \
  --namespace crossplane-system

kubectl -n crossplane-system get pod -w
# crossplane-...          Running
# crossplane-rbac-...     Running
```

```bash
# Crossplane이 추가한 CRD 확인 (08의 CRD 개념)
kubectl get crd | grep crossplane
# compositeresourcedefinitions.apiextensions.crossplane.io
# compositions.apiextensions.crossplane.io
# providers.pkg.crossplane.io
# ...
```

Crossplane 코어는 아직 아무 클라우드도 모릅니다 — Provider를 깔아야 특정 클라우드를 압니다.

## 2. Provider 설치 (provider-nop — 가짜, 개념용)

실제 클라우드 대신, 아무 실제 리소스도 만들지 않지만 **조정 루프는 똑같이 도는** `provider-nop`으로 개념을 익힙니다.

```yaml
# provider.yaml
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-nop
spec:
  package: xpkg.upbound.io/crossplane-contrib/provider-nop:v0.4.0
```

```bash
kubectl apply -f provider.yaml

# Provider가 설치·헬시해지는 과정 (Crossplane이 컨트롤러를 배포)
kubectl get provider -w
# NAME           INSTALLED   HEALTHY
# provider-nop   True        True

# Provider가 추가한 CRD (이제 nop 리소스 타입이 생김)
kubectl get crd | grep nop
# nopresources.nop.crossplane.io
```

**39·40과 비교** — Strimzi/Rook 오퍼레이터가 CRD를 추가했듯, Provider도 컨트롤러+CRD를 추가합니다. 같은 08의 패턴이 "클라우드 Provider" 형태로 반복됩니다.

## 3. Managed Resource 생성 — 조정 관찰

```yaml
# mr.yaml — nop 리소스 하나 (실제 클라우드였다면 RDSInstance 같은 것)
apiVersion: nop.crossplane.io/v1alpha1
kind: NopResource
metadata:
  name: my-resource
spec:
  forProvider:
    conditionAfter:
      - conditionType: Ready
        conditionStatus: "True"
        time: 10s              # 10초 뒤 Ready로 (실제 프로비저닝 흉내)
  writeConnectionSecretToRef:
    name: my-resource-conn
    namespace: crossplane-system
```

```bash
kubectl apply -f mr.yaml

# 조정 관찰: 처음엔 Ready=False, 10초 뒤 True (08의 조정 루프)
kubectl get nopresource my-resource -w
# NAME          READY   SYNCED   AGE
# my-resource   False   True     2s      ← 조정 시작
# my-resource   True    True     12s     ← 원하는 상태 도달

# 상세: spec(원하는 상태)과 status(실제)
kubectl describe nopresource my-resource
# Status:
#   Conditions:
#     Type: Synced   Status: True   (Crossplane이 provider와 동기화)
#     Type: Ready    Status: True   (실제 리소스가 준비됨)
```

**핵심** — `SYNCED`(Crossplane이 원하는 상태를 provider에 반영했나)와 `READY`(실제 리소스가 준비됐나)가 나뉩니다. 이것이 08의 spec↔status 조정이 인프라 수준에서 도는 모습입니다. 실제 provider-aws였다면 이 사이에 AWS API 호출로 진짜 RDS가 생겼을 것입니다.

## 4. 드리프트 교정 개념 (Crossplane의 핵심 차별점)

```bash
# Crossplane은 계속 조정합니다 — status를 지워도 다시 채웁니다
# (실제 클라우드였다면: 콘솔에서 누가 바꿔도 Crossplane이 되돌림)

# 조정 주기 확인
kubectl get nopresource my-resource -o yaml | grep -A2 "conditions:"
# Crossplane 컨트롤러가 주기적으로(기본 짧은 간격) 실제와 spec을 비교

# 리소스를 지우면?
kubectl delete nopresource my-resource
# → Crossplane이 실제 클라우드 리소스도 삭제 (finalizer로 정리 보장)
```

**Terraform과 대비** — Terraform이라면 `apply` 시점에만 상태를 맞추고, 그 사이 드리프트는 다음 apply까지 방치됩니다. Crossplane은 컨트롤러가 상시 돌며 드리프트를 자동 교정합니다(theory 4절). 이것이 "일회성 vs 지속 조정"의 실체입니다.

## 5. 연결 정보 (Connection Secret)

```bash
# MR이 만든 연결 정보가 Secret으로 (실제라면 DB 접속 정보)
kubectl -n crossplane-system get secret my-resource-conn
# → 앱이 이 Secret을 마운트해 인프라에 접속 (07의 Secret)
```

이 Secret 메커니즘 덕에, Composition(lab-02)이 만든 DB의 접속 정보가 자동으로 앱에 전달됩니다 — 개발자는 접속 문자열을 손으로 관리하지 않습니다.

## 6. 정리

```bash
kubectl delete -f mr.yaml 2>/dev/null || true
kubectl delete -f provider.yaml 2>/dev/null || true
# 클러스터는 cleanup.sh에서
```

## 정리

- Crossplane 코어 + Provider(클라우드별 컨트롤러+CRD) — 08의 오퍼레이터 패턴이 인프라로
- Managed Resource = 클라우드 리소스 1:1 CR, 조정 루프가 spec↔실제를 맞춤
- `SYNCED`(provider 반영) vs `READY`(실제 준비) — 08의 spec↔status
- **드리프트 자동 교정** — Terraform의 일회성 apply와 다른 지속 조정
- Connection Secret으로 인프라 접속 정보가 앱에 자동 전달(07)
- **★ K8s 조정 루프가 클라우드 인프라를 다스립니다 — "K8s API = 범용 컨트롤 플레인"**
