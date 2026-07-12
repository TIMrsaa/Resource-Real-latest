# 이론 — Kustomize: base, overlay, 패치, 제너레이터

> **🌱 17세 눈높이 비유: 학급 단체 티셔츠 주문**
> 기본 디자인 시안(base)은 완성된 그림입니다. 반별 주문은 시안을 고치는 게 아니라 **수정 스티커(패치)** 를 붙입니다: "3반은 등번호만 파랑으로", "7반은 사이즈만 XL". 원본 시안은 영원히 깨끗하고, 반별 차이는 스티커 몇 장으로 추적됩니다.

---

## 1. kustomization.yaml — 조립 설명서

```yaml
# base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:               # 포함할 리소스 (완전한 YAML들)
- deployment.yaml
- service.yaml
labels:                  # 모든 리소스에 라벨 일괄 부여
- pairs: { app.kubernetes.io/part-of: shop }
  includeSelectors: false
```

```yaml
# overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base             # base를 통째로 가져와서
namespace: shop-prod     # ns 일괄 지정
namePrefix: prod-        # 이름 접두사
patches:                 # 패치를 얹습니다
- path: replicas-patch.yaml
- target: { kind: Deployment, name: web }
  patch: |-
    - op: add
      path: /spec/template/spec/containers/0/resources
      value: { requests: { cpu: 200m } }
images:                  # 이미지 태그 교체 단축 문법
- name: myapp
  newTag: v1.4.2
```

빌드: `kubectl kustomize overlays/prod` (보기) / `kubectl apply -k overlays/prod` (적용). 별도 설치 없이 kubectl 내장.

## 2. 패치 2형식

### strategic merge patch — "부분 YAML 겹치기"

```yaml
# replicas-patch.yaml — 바꿀 부분만 적은 미니 Deployment
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }       # 대상 식별 (kind+name)
spec:
  replicas: 5
```

직관적. 리스트(컨테이너)는 name 키로 병합(모듈 10의 patchMergeKey와 동일 원리).

### JSON6902 patch — "경로 수술"

```yaml
- op: replace                  # add / remove / replace
  path: /spec/template/spec/containers/0/image
  value: myapp:v2
```

배열 인덱스 등 정밀 조작, strategic merge가 못 하는 삭제(remove)에 사용.

## 3. 제너레이터 — 해시의 마법

```yaml
configMapGenerator:
- name: app-config
  literals: [LOG_LEVEL=info]
  files: [config.properties]
secretGenerator:
- name: db-cred
  envs: [.env.secret]          # Git에는 안 올리는 파일
```

빌드 결과: `app-config-7f9h2k4tm5` — **내용 해시가 접미사로.** 그리고 이 ConfigMap을 참조하는 모든 곳(Deployment의 volumes/envFrom)의 이름도 **자동으로 같이 바뀝니다.**

효과 사슬: 설정 변경 → 새 이름의 CM 생성 → Deployment template 변경 → **자동 롤링 업데이트** → 옛 CM은 잔존(롤백 대비). 모듈 07의 "이름 해시 + 교체" 운영 패턴의 완전 자동화입니다.

## 4. 자주 쓰는 변형 필드 요약

| 필드 | 용도 |
|------|------|
| namespace / namePrefix / nameSuffix | 일괄 네이밍 |
| labels / commonAnnotations | 일괄 메타데이터 |
| images | 이미지/태그 교체 (CI가 sed 대신 쓰는 것) |
| replicas | replicas만 빠르게 |
| components | 선택적 기능 묶음 (멀티 오버레이 재사용) |
| helmCharts | (제한적) 차트 인플레이션 — CLI는 --enable-helm 필요 |

## 5. Helm과의 조합 — 실무 표준 패턴

```bash
# 외부 차트를 받아 회사 표준(라벨, 사이드카, 보안설정)을 패치로 강제
helm template ingress-nginx ingress-nginx/ingress-nginx --version x.y.z \
  > base/ingress-nginx.yaml
kubectl apply -k overlays/prod
# 또는 파이프: helm template ... | kubectl kustomize --stdin (도구에 따라)
```

ArgoCD/Flux는 이 조합을 내장 지원합니다(차트 + kustomize 후처리) — cicd 파트 14~15.

## 6. 소스코드에서 확인하기

- kustomize 본체: https://github.com/kubernetes-sigs/kustomize — `api/krusty/kustomizer.go`가 빌드 파이프라인, 해시는 `api/hasher/`
- kubectl 내장 경로: `staging/src/k8s.io/cli-runtime/pkg/resource` 와 연결

## 요약 카드

| 질문 | 답 |
|------|----|
| Kustomize의 원본 철학? | 항상 유효한 YAML + 패치 겹치기 (템플릿 없음) |
| 적용 명령? | `kubectl apply -k <dir>` (내장) |
| 패치 2형식? | strategic merge(부분 YAML) / JSON6902(경로 연산) |
| configMapGenerator의 가치? | 내용 해시 이름 + 참조 자동 갱신 → 설정 변경 시 자동 롤링 |
| Helm과의 분업? | 외부 제품=Helm, 자사 환경 분리/후처리=Kustomize |
