# Lab 01 — 클라이언트 4종 체험

## Step 0. 프로젝트 준비

```bash
mkdir -p ~/clientgo-lab && cd ~/clientgo-lab
go mod init example.com/clientgo-lab
go get k8s.io/client-go@latest k8s.io/apimachinery@latest
```

## Step 1. clientset — 정적 타입의 안정감

`main.go`:

```go
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

func main() {
	kubeconfig := flag.String("kubeconfig", filepath.Join(os.Getenv("HOME"), ".kube", "config"), "")
	flag.Parse()
	cfg, err := clientcmd.BuildConfigFromFlags("", *kubeconfig)
	if err != nil { panic(err) }
	cs := kubernetes.NewForConfigOrDie(cfg)

	pods, err := cs.CoreV1().Pods("kube-system").List(context.TODO(), metav1.ListOptions{})
	if err != nil { panic(err) }
	for _, p := range pods.Items {
		fmt.Printf("%-50s %s\n", p.Name, p.Status.Phase)   // p.Status.Phase — 컴파일 타임 타입!
	}
}
```

```bash
go run . | head -5
```

예상: kube-system Pod 목록. `p.Status.Phase`에서 오타를 내보세요 — **컴파일 에러**로 잡힙니다 (jsonpath 오타가 런타임에 빈 문자열로 침묵하는 것과의 차이).

## Step 2. dynamic — CRD를 타입 없이

모듈 24/30의 Website CRD가 지워졌으므로 아무 CRD나(예: EKS에 있는 ENIConfig) 또는 내장 리소스를 GVR로:

```go
// dynamic.go (별도 파일로 만들어 main 함수만 바꿔 실행해보세요)
import (
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
)

dyn := dynamic.NewForConfigOrDie(cfg)
gvr := schema.GroupVersionResource{Group: "apps", Version: "v1", Resource: "deployments"}
list, _ := dyn.Resource(gvr).Namespace("kube-system").List(ctx, metav1.ListOptions{})
for _, item := range list.Items {
	// Unstructured = map[string]interface{} — 경로 탐색 헬퍼 사용
	replicas, found, _ := unstructured.NestedInt64(item.Object, "spec", "replicas")
	fmt.Println(item.GetName(), replicas, found)
}
```

✅ 타입 정의 없이 **GVR 문자열만으로** 아무 리소스나 — kubectl과 GitOps 도구들이 임의 리소스를 다루는 방법이 이것입니다. 대가는 런타임 에러 위험(found 체크!).

## Step 3. discovery — 클러스터의 메뉴판

```go
disco := discovery.NewDiscoveryClientForConfigOrDie(cfg)
lists, _ := disco.ServerPreferredResources()
for _, l := range lists {
	for _, r := range l.APIResources {
		if r.Namespaced && strings.Contains(r.Name, "/") == false {
			fmt.Println(l.GroupVersion, r.Name, r.ShortNames)
		}
	}
}
```

✅ `kubectl api-resources`의 구현 원리. dynamic과 조합하면 "클러스터에 있는 모든 리소스를 순회"하는 도구(백업, 감사 스캐너)를 만들 수 있습니다 — Velero류의 뼈대.

## Step 4. 쓰기 + RetryOnConflict

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: retry-target
  labels: { app: retry-target }
spec:
  replicas: 1
  selector:
    matchLabels: { app: retry-target }
  template:
    metadata:
      labels: { app: retry-target }
    spec:
      containers:
        - name: retry-target
          image: public.ecr.aws/nginx/nginx:1.27
EOF
```

```go
import "k8s.io/client-go/util/retry"

err = retry.RetryOnConflict(retry.DefaultRetry, func() error {
	d, err := cs.AppsV1().Deployments("default").Get(ctx, "retry-target", metav1.GetOptions{})
	if err != nil { return err }
	if d.Annotations == nil { d.Annotations = map[string]string{} }
	d.Annotations["touched-by"] = "clientgo-lab"
	_, err = cs.AppsV1().Deployments("default").Update(ctx, d, metav1.UpdateOptions{})
	return err          // 409면 RetryOnConflict가 다시 Get부터
})
```

✅ 모듈 21에서 재현했던 409의 **표준 처방전.** "다시 읽고 다시 시도"가 라이브러리 한 줄.

## Step 5. -v=8 비교 관찰

```bash
kubectl get pods -n kube-system -v=8 2>&1 | grep GET | head -2
```

우리 Go 코드가 친 것과 같은 URL — kubectl도 clientset의 사촌일 뿐임을 재확인.

## 정리

```bash
kubectl delete deployment retry-target --ignore-not-found
# 프로젝트는 lab-02에서 계속
```
