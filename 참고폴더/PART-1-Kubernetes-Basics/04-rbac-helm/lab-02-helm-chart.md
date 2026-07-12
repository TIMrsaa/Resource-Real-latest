# Lab 02 — Helm 차트 작성

## 학습 확인 포인트

- [ ] 차트의 5개 표준 파일 역할을 안다 (`Chart.yaml`, `values.yaml`, `templates/_helpers.tpl`, `templates/deployment.yaml`, `templates/service.yaml`)
- [ ] `helm template` 으로 렌더 결과를 미리 본다
- [ ] values 오버라이드 (`-f`, `--set`) 방식을 안다

> **🌱 핵심 개념 미리보기**
> - **Helm Chart**: K8s 매니페스트 YAML 묶음을 템플릿화 + 패키징한 단위. apt/yum의 패키지 같은 개념.
> - **Chart.yaml**: 차트 메타정보 (이름, 버전, 의존성).
> - **values.yaml**: 템플릿에 주입될 기본 값들. 사용자가 오버라이드 가능.
> - **templates/**: Go 템플릿 문법으로 작성된 K8s 매니페스트들. `{{ .Values.image.tag }}` 처럼 값 참조.
> - **release**: helm install 한 차트의 인스턴스. 같은 차트 다른 release 이름으로 여러 번 설치 가능.

## 1. 미리 만들어진 차트 살펴보기

본 모듈 폴더의 [`charts/order-service/`](./charts/order-service/) 가 그것입니다.

```bash
cd charts/order-service
ls -la
ls templates/
```

기대:
```
Chart.yaml
values.yaml
.helmignore
templates/
  _helpers.tpl
  deployment.yaml
  service.yaml
  hpa.yaml
  ingress.yaml
```

## 2. lint

```bash
helm lint .
```

기대:
```
==> Linting .
[INFO] Chart.yaml: icon is recommended
1 chart(s) linted, 0 chart(s) failed
```

## 3. 템플릿 렌더 미리보기 (배포 X)

```bash
helm template demo . --set image.repository=test/order-service
```

기대: Deployment + Service 매니페스트가 출력됨. `demo-order-service` 가 fullname.

> **🧠 `helm template` 은 K8s에 아무것도 안 보냄**
> 순수 클라이언트 사이드 렌더링 — 템플릿 + values 를 합쳐 YAML 출력만 하고 끝.
> 디버깅 시 `--debug`, 특정 값 확인 시 `--show-only templates/deployment.yaml` 같은 옵션 유용.
> CI에서 PR 때 `helm template` 결과를 git diff 로 보면 변경 영향 파악 쉬움 (helm-diff plugin 도 있음).

다양한 values를 주면서 비교:
```bash
helm template demo . --set image.repository=test/order-service --set replicaCount=5
helm template demo . --set image.repository=test/order-service --set autoscaling.enabled=true
helm template demo . --set image.repository=test/order-service --set ingress.enabled=true
```

## 4. 필수 값 누락 시 에러

```bash
helm template demo .            # image.repository 미지정
```

기대:
```
Error: execution error at (.../templates/deployment.yaml): image.repository is required
```

`{{ required "..." .Values.image.repository }}` 문법으로 강제 가능.

> **🧠 values 우선순위 (낮음 → 높음)**
> 1. 차트의 `values.yaml` (기본값)
> 2. `-f custom.yaml` (파일로 오버라이드, 여러 -f 시 뒤가 우선)
> 3. `--set key=val` (CLI 인라인, 가장 우선)
> 같은 키가 여러 곳에 있으면 위 순서로 덮어씀. 운영에선 환경별 values-{env}.yaml 파일을 git에, 비밀값만 --set 으로.

## 5. 실제 EKS에 dry-run 설치

ECR에 order-service 이미지가 푸시되어 있다고 가정. ([`00-prerequisites/scripts/ecr-push-all.sh`](../../00-prerequisites/scripts/ecr-push-all.sh))

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2
REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/eks-study/order-service"

helm install demo . \
  --set image.repository=$REPO \
  --set image.tag=latest \
  --dry-run --debug \
  | head -80
```

## 6. 실제 설치

```bash
helm install demo . \
  --set image.repository=$REPO \
  --set image.tag=latest \
  --namespace demo --create-namespace

helm list -A
kubectl get deploy,svc,pod -n demo
```

## 7. 업그레이드

values 일부만 변경:
```bash
helm upgrade demo . \
  --set image.repository=$REPO \
  --set replicaCount=4 \
  -n demo
```

```bash
kubectl get pods -n demo --watch
```

기대: replicas가 2 → 4로.

## 8. 이력 / 롤백

```bash
helm history demo -n demo
helm rollback demo 1 -n demo
helm history demo -n demo            # 새 revision으로 롤백 기록 추가
```

> **🧠 Helm은 release 정보를 어디 저장하나**
> 기본적으로 같은 NS의 Secret(`sh.helm.release.v1.<name>.v<rev>`) 에 압축해 저장.
> = K8s 만 있으면 Helm 메타데이터가 따라옴 → 다른 머신에서도 `helm list` 가능.
> rollback 은 옛 revision 의 매니페스트를 다시 apply 하면서 **새 revision 번호 부여** (히스토리 보존).

## 9. 정리

```bash
helm uninstall demo -n demo
kubectl delete ns demo
```

## 학습 확인 질문

1. `helm template` 과 `helm install --dry-run` 의 차이점은?
2. `helm rollback` 은 어느 revision으로 되돌리는가? 새 revision을 만드는가, 아니면 이전 revision 자체를 활성화하는가?
3. `values.yaml` 의 값이 `--set` CLI보다 우선순위가 높을까?

다음: [mini-project.md](./mini-project.md)
