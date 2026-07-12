# Lab 01 — 스캐폴드와 API 타입 정의

> **환경**: WSL2/리눅스에 Go 1.24+, kubebuilder CLI. 설치:
> ```bash
> go version   # 1.24+
> curl -L -o kubebuilder https://go.kubebuilder.io/dl/latest/linux/amd64 && chmod +x kubebuilder && sudo mv kubebuilder /usr/local/bin/
> ```

## Step 1. 프로젝트 스캐폴드

```bash
mkdir -p ~/website-operator && cd ~/website-operator
kubebuilder init --domain example.com --repo example.com/website-operator
kubebuilder create api --group platform --version v1 --kind Website --resource --controller
find . -name "*.go" | grep -v test | head
```

예상 구조:
```
api/v1/website_types.go              ← 우리가 채울 곳 ①
internal/controller/website_controller.go   ← 우리가 채울 곳 ②
config/crd/, config/rbac/, ...       ← make manifests가 채우는 곳
cmd/main.go                          ← Manager 기동부 (읽어볼 것)
```

## Step 2. API 타입 작성

`api/v1/website_types.go`의 Spec/Status를 교체:

```go
// WebsiteSpec defines the desired state of Website
type WebsiteSpec struct {
	// 컨테이너 이미지 (태그 필수)
	// +kubebuilder:validation:Pattern=`^.+:.+$`
	Image string `json:"image"`

	// 복제본 수
	// +kubebuilder:validation:Minimum=1
	// +kubebuilder:validation:Maximum=10
	Replicas int32 `json:"replicas"`
}

// WebsiteStatus defines the observed state of Website
type WebsiteStatus struct {
	ReadyReplicas int32  `json:"readyReplicas,omitempty"`
	Phase         string `json:"phase,omitempty"`
}
```

Website struct 위의 마커에 추가 (이미 일부 있음 — 합쳐서):

```go
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="Ready",type=integer,JSONPath=`.status.readyReplicas`
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=`.status.phase`
```

## Step 3. CRD 생성/설치 — Go가 YAML이 되는 순간

```bash
make manifests
grep -A5 "pattern" config/crd/bases/platform.example.com_websites.yaml | head -8
```

예상: 우리가 마커로 쓴 `pattern: ^.+:.+$`, minimum/maximum이 **모듈 24에서 손으로 썼던 그 CRD 스키마**로 생성되어 있습니다.

```bash
make install        # CRD를 클러스터(EKS)에 설치
kubectl get crd websites.platform.example.com
kubectl explain website.spec
```

✅ explain에 우리가 쓴 Go 주석이 문서로 나옵니다 — **주석까지 API 문서가 됩니다.**

## Step 4. 샘플 CR과 "아직 아무 일도 없음" 확인

```bash
cat > config/samples/platform_v1_website.yaml <<'EOF'
apiVersion: platform.example.com/v1
kind: Website
metadata: { name: blog }
spec:
  image: public.ecr.aws/nginx/nginx:1.27
  replicas: 2
EOF
kubectl apply -f config/samples/platform_v1_website.yaml
kubectl get website
```

예상: blog가 생겼지만 READY/PHASE 빈칸, Deployment도 없음 — 컨트롤러(동사)가 아직 빈 껍데기니까. lab-02에서 채웁니다.

## Step 5. 빈 컨트롤러라도 일단 돌려보기 (개발 루프 체험)

```bash
make run
```

예상 출력: Manager 기동, informer 캐시 동기화 로그 후 대기. 다른 터미널에서 `kubectl annotate website blog test=1` 등으로 변경을 가하면 (기본 스캐폴드의) Reconcile이 호출되는 로그가 찍힙니다 — **노트북의 프로세스가 EKS를 watch하고 있습니다.** Ctrl+C로 중단.

## 정리

다음 lab에서 이어서 구현. 프로젝트 유지.
