# helm 치트시트

## 리포지토리

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add eks https://aws.github.io/eks-charts
helm repo add karpenter oci://public.ecr.aws/karpenter   # OCI registry
helm repo add kedacore https://kedacore.github.io/charts

helm repo list
helm repo update
helm repo remove bitnami
```

## 차트 검색 / 정보

```bash
helm search repo nginx
helm search hub nginx                                    # ArtifactHub 검색
helm show chart bitnami/nginx
helm show values bitnami/nginx > values.yaml             # 기본 values 출력
helm show readme bitnami/nginx
```

## 설치 / 업그레이드

```bash
# 기본 설치
helm install my-nginx bitnami/nginx -n web --create-namespace

# values 파일로
helm install my-nginx bitnami/nginx -f values.yaml

# 인라인 set
helm install my-nginx bitnami/nginx \
  --set replicaCount=3 \
  --set image.tag=1.27.0

# 업그레이드 (없으면 install)
helm upgrade --install my-nginx bitnami/nginx -f values.yaml --namespace web

# 특정 버전
helm install my-nginx bitnami/nginx --version 15.0.0

# OCI 레지스트리 (Karpenter 등)
helm install karpenter oci://public.ecr.aws/karpenter/karpenter --version 1.0.0
```

## 검증 / 진단 (--dry-run)

```bash
helm install my-nginx bitnami/nginx --dry-run --debug
helm template my-nginx bitnami/nginx > rendered.yaml      # YAML로 렌더만
helm lint ./mychart                                       # 차트 검증
```

## 릴리즈 관리

```bash
helm list                                                 # 현재 NS
helm list -A                                              # 전체 NS
helm list -n kube-system

helm status my-nginx
helm get values my-nginx
helm get manifest my-nginx
helm history my-nginx
helm rollback my-nginx 1                                  # 1번 리비전으로
helm uninstall my-nginx -n web
```

## 차트 만들기

```bash
helm create mychart
# 구조:
# mychart/
# ├── Chart.yaml
# ├── values.yaml
# ├── templates/
# │   ├── _helpers.tpl
# │   ├── deployment.yaml
# │   ├── service.yaml
# │   └── ingress.yaml
# └── charts/   (subchart)
```

## values 우선순위 (낮음 → 높음)

1. `values.yaml` (차트 내부 기본값)
2. `-f values-prod.yaml`
3. `--set` (CLI)

## 의존성 (subchart)

```yaml
# Chart.yaml
dependencies:
  - name: postgresql
    version: 13.x.x
    repository: https://charts.bitnami.com/bitnami
```

```bash
helm dependency update ./mychart    # charts/ 디렉토리에 다운로드
helm dependency build ./mychart
```

## 패키징 / 배포

```bash
helm package ./mychart                # mychart-0.1.0.tgz 생성
helm repo index .                     # index.yaml 생성 (자체 호스팅)
helm push mychart-0.1.0.tgz oci://my-registry.com/charts
```

## 흔한 패턴

```bash
# values.yaml 일부만 override + 나머지는 기본값
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "1.0.0" \
  --namespace karpenter \
  --create-namespace \
  --set "settings.clusterName=eks-study" \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=arn:aws:iam::xxx:role/yyy" \
  --wait

# 업그레이드 시 변경된 부분만 보기
helm diff upgrade my-nginx bitnami/nginx -f values.yaml   # plugin 필요
```
