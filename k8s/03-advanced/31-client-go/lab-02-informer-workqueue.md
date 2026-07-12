# Lab 02 — informer + workqueue로 미니 컨트롤러를 맨손 조립

> 목표물: "라벨 `watch=me`가 붙은 ConfigMap을 감시해, data 키 개수를 annotation으로 기록"하는 장난감 컨트롤러. 비즈니스 로직은 사소하지만 **배관은 ReplicaSet 컨트롤러와 동일 구조**입니다.

## Step 1. 전체 코드

`controller.go` (lab-01 프로젝트에 추가, main 교체):

```go
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/util/retry"
	"k8s.io/client-go/util/workqueue"
)

func main() {
	kubeconfig := flag.String("kubeconfig", filepath.Join(os.Getenv("HOME"), ".kube", "config"), "")
	flag.Parse()
	cfg, _ := clientcmd.BuildConfigFromFlags("", *kubeconfig)
	cs := kubernetes.NewForConfigOrDie(cfg)

	// ① SharedInformerFactory — 라벨 셀렉터로 watch 범위 최소화! (모듈 21 매너)
	factory := informers.NewSharedInformerFactoryWithOptions(cs, 10*time.Hour,
		informers.WithTweakListOptions(func(o *metav1.ListOptions) { o.LabelSelector = "watch=me" }))
	cmInformer := factory.Core().V1().ConfigMaps()

	// ② RateLimitingQueue
	queue := workqueue.NewTypedRateLimitingQueue(workqueue.DefaultTypedControllerRateLimiter[string]())

	// ③ 핸들러: 무슨 일이 났든 "키만" 큐에
	cmInformer.Informer().AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc: func(obj interface{}) { enqueue(queue, obj) },
		UpdateFunc: func(_, newObj interface{}) { enqueue(queue, newObj) },
		DeleteFunc: func(obj interface{}) { enqueue(queue, obj) },
	})

	stop := make(chan struct{})
	defer close(stop)
	factory.Start(stop)                                    // Reflector 가동 (List+Watch)
	if !cache.WaitForCacheSync(stop, cmInformer.Informer().HasSynced) {
		panic("cache sync failed")                          // ★ 캐시 동기화 전 처리 금지!
	}
	fmt.Println("cache synced — controller running")

	// ④ 워커 (2개 병렬 — 같은 키는 큐가 직렬화해줌)
	for i := 0; i < 2; i++ {
		go func() {
			for {
				key, shutdown := queue.Get()
				if shutdown { return }
				func() {
					defer queue.Done(key)
					if err := reconcile(cs, cmInformer, key); err != nil {
						fmt.Println("error, requeue:", key, err)
						queue.AddRateLimited(key)            // 실패 → 백오프
						return
					}
					queue.Forget(key)                        // 성공 → 카운터 리셋
				}()
			}
		}()
	}
	select {} // 영원히
}

func enqueue(q workqueue.TypedRateLimitingInterface[string], obj interface{}) {
	if key, err := cache.MetaNamespaceKeyFunc(obj); err == nil {
		q.Add(key)        // "default/my-cm" 형태의 키만!
	}
}

func reconcile(cs *kubernetes.Clientset, inf informers.../*v1.ConfigMapInformer*/, key string) error {
	ns, name, _ := cache.SplitMetaNamespaceKey(key)
	// ⑤ 읽기는 캐시(Lister)에서 — API 호출 0
	cm, err := inf.Lister().ConfigMaps(ns).Get(name)
	if err != nil { return nil }   // 삭제된 경우 — 이 장난감은 할 일 없음
	want := fmt.Sprintf("%d", len(cm.Data))
	if cm.Annotations["key-count"] == want { return nil }   // 이미 수렴 — 쓰기 생략 (루프 방지!)
	// ⑥ 쓰기는 API로 + conflict 재시도
	return retry.RetryOnConflict(retry.DefaultRetry, func() error {
		fresh, err := cs.CoreV1().ConfigMaps(ns).Get(context.TODO(), name, metav1.GetOptions{})
		if err != nil { return err }
		if fresh.Annotations == nil { fresh.Annotations = map[string]string{} }
		fresh.Annotations["key-count"] = fmt.Sprintf("%d", len(fresh.Data))
		_, err = cs.CoreV1().ConfigMaps(ns).Update(context.TODO(), fresh, metav1.UpdateOptions{})
		return err
	})
}
```

(import 정리는 goimports에 맡겨라: `go run golang.org/x/tools/cmd/goimports@latest -w .`)

```bash
go run .
```

## Step 2. 동작 검증

다른 터미널:
```bash
kubectl create configmap tracked --from-literal=a=1 --from-literal=b=2
kubectl label configmap tracked watch=me
sleep 2
kubectl get cm tracked -o jsonpath='{.metadata.annotations.key-count}'; echo    # → 2

kubectl patch cm tracked --type=merge -p '{"data":{"c":"3"}}'
sleep 2
kubectl get cm tracked -o jsonpath='{.metadata.annotations.key-count}'; echo    # → 3 (자동 갱신!)
```

✅ watch → 캐시 → 키 큐잉 → 워커 reconcile — **컨트롤러 배관 풀세트가 내 손으로 조립됐습니다.**

## Step 3. 구조 퀴즈를 코드로 확인

1. **중복 압축**: 컨트롤러를 잠시 Ctrl+Z로 멈추고 `kubectl patch`를 5번 연속 → fg로 재개 → reconcile 로그가 **1~2번**만 (큐가 압축)
2. **라벨 밖은 투명**: `watch=me` 없는 ConfigMap을 아무리 바꿔도 핸들러 침묵 — watch 범위 최소화의 효과
3. **수렴 체크의 가치**: reconcile의 "이미 수렴 — 쓰기 생략" 줄을 주석 처리하면? — 우리 쓰기(annotation)가 Update 이벤트를 만들고 → 또 reconcile → 무한 루프의 씨앗 (모듈 30 pitfall 3을 맨살로 체험)

## Step 4. controller-runtime과의 대조 (졸업 정리)

| 우리가 손으로 한 것 | controller-runtime에서 |
|---------------------|------------------------|
| factory/informer/캐시 sync | Manager가 자동 |
| 핸들러→큐 배선 | For()/Owns() |
| 워커 루프 + Done/Forget | 프레임워크 내부 |
| reconcile(키) | Reconcile(ctx, req) — 시그니처가 같습니다! |

✅ 이제 모듈 30의 "마법"이 전부 설명 가능한 부품이 됐습니다. 그리고 `pkg/controller/replicaset/replica_set.go`를 열어보세요 — **같은 배관이 보일 것입니다** (기여자 트랙 입장권).

## 정리

```bash
kubectl delete configmap tracked --ignore-not-found
```
