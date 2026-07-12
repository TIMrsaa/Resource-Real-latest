# Lab 02 — Reconcile 구현: Website → Deployment 동기화

## Step 1. Reconciler 구현

`internal/controller/website_controller.go`를 다음으로 교체 (import는 IDE/goimports에 맡기거나 아래 참고):

```go
package controller

import (
	"context"
	"fmt"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	platformv1 "example.com/website-operator/api/v1"
)

type WebsiteReconciler struct {
	client.Client
	Scheme *runtime.Scheme // import "k8s.io/apimachinery/pkg/runtime"
}

// +kubebuilder:rbac:groups=platform.example.com,resources=websites,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=platform.example.com,resources=websites/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete

func (r *WebsiteReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := logf.FromContext(ctx)

	// 1. 대상 Website 읽기
	var site platformv1.Website
	if err := r.Get(ctx, req.NamespacedName, &site); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err) // 삭제됨 → GC가 자식 정리
	}

	// 2. 원하는 자식(Deployment) 선언
	labels := map[string]string{"app": site.Name, "managed-by": "website-operator"}
	deploy := &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{Name: site.Name, Namespace: site.Namespace},
		Spec: appsv1.DeploymentSpec{
			Replicas: &site.Spec.Replicas,
			Selector: &metav1.LabelSelector{MatchLabels: labels},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{Labels: labels},
				Spec: corev1.PodSpec{Containers: []corev1.Container{{
					Name:  "web",
					Image: site.Spec.Image,
					Ports: []corev1.ContainerPort{{ContainerPort: 80}},
				}}},
			},
		},
	}
	deploy.SetGroupVersionKind(appsv1.SchemeGroupVersion.WithKind("Deployment")) // SSA에 필요

	// 3. ownerReference — "내 자식" 표시 (GC + Owns 워치의 토대)
	if err := ctrl.SetControllerReference(&site, deploy, r.Scheme); err != nil {
		return ctrl.Result{}, err
	}

	// 4. Server-Side Apply — 없으면 생성, 있으면 수렴 (멱등!)
	if err := r.Patch(ctx, deploy, client.Apply,
		client.FieldOwner("website-operator"), client.ForceOwnership); err != nil {
		return ctrl.Result{}, err // 에러 반환 = 자동 백오프 재시도
	}

	// 5. status 보고 — 자식의 현재 상태를 읽어서
	var current appsv1.Deployment
	if err := r.Get(ctx, req.NamespacedName, &current); err == nil {
		site.Status.ReadyReplicas = current.Status.ReadyReplicas
		if current.Status.ReadyReplicas == site.Spec.Replicas {
			site.Status.Phase = "Ready"
		} else {
			site.Status.Phase = "Progressing"
		}
		if err := r.Status().Update(ctx, &site); err != nil {
			return ctrl.Result{}, err
		}
	}

	log.Info("reconciled", "website", site.Name, "ready", site.Status.ReadyReplicas)
	return ctrl.Result{}, nil
}

func (r *WebsiteReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&platformv1.Website{}).
		Owns(&appsv1.Deployment{}). // ★ 자식의 변화도 나를 깨웁니다
		Complete(r)
}
```

```bash
make manifests && make run
```

## Step 2. 탄생 검증

다른 터미널:
```bash
kubectl get website,deploy,pods -l app=blog 2>/dev/null; kubectl get website
```

예상 출력:
```
NAME   READY   PHASE
blog   2       Ready          ← status가 채워졌습니다!
deployment.apps/blog   2/2    ← 컨트롤러가 만든 자식
```

✅ **모듈 24의 빈 명사가 드디어 동사를 얻었습니다.** make run 터미널의 reconcile 로그도 확인.

## Step 3. 조정 루프 3종 검증 (모듈 02의 패턴을 내 코드로)

```bash
# ① spec 변경 → 수렴
kubectl patch website blog --type=merge -p '{"spec":{"replicas":4}}'
kubectl get deploy blog -o jsonpath='{.spec.replicas}'; echo    # → 4

# ② 자식 파괴 → 부활 (Owns 배선의 효과)
kubectl delete deployment blog
sleep 3; kubectl get deploy blog                                 # → 다시 존재!

# ③ 자식 변조 → 원복 (SSA 수렴)
kubectl patch deploy blog --type=merge -p '{"spec":{"replicas":9}}'
sleep 3; kubectl get deploy blog -o jsonpath='{.spec.replicas}'; echo   # → 4 (내 선언으로 복원)
```

✅ 생성/치유/드리프트 복원 — **우리가 만든 컨트롤러가 ReplicaSet 컨트롤러와 같은 부류의 생물**이 됐습니다. ③이 GitOps self-heal(모듈 39)의 원리이기도 합니다.

## Step 4. 부모 삭제 → GC 연쇄

```bash
kubectl delete website blog
sleep 3; kubectl get deploy blog
```

예상: NotFound — 컨트롤러는 삭제 코드를 한 줄도 안 짰습니다. **SetControllerReference + GC**(모듈 24)가 다 했습니다.

## Step 5. (선택 심화) finalizer로 외부 자원 정리

"Website 삭제 시 외부 DNS 레코드도 지워야 한다"는 요구가 생기면 — Reconcile 앞부분에:

```go
const finalizer = "platform.example.com/dns-cleanup"
if site.DeletionTimestamp.IsZero() {
    if !controllerutil.ContainsFinalizer(&site, finalizer) {
        controllerutil.AddFinalizer(&site, finalizer)
        if err := r.Update(ctx, &site); err != nil { return ctrl.Result{}, err }
    }
} else {
    // 삭제 진행 중 — 외부 정리 후 finalizer 제거
    if controllerutil.ContainsFinalizer(&site, finalizer) {
        // deleteExternalDNS(site)  ← 실제 정리
        controllerutil.RemoveFinalizer(&site, finalizer)
        if err := r.Update(ctx, &site); err != nil { return ctrl.Result{}, err }
    }
    return ctrl.Result{}, nil
}
```

모듈 24 Part B에서 손으로 했던 그 시나리오가 코드 패턴으로. **추가했다면 제거 경로도 함께**라는 pitfall도 그대로 적용됩니다.

## Step 6. 배포까지 (참고 절차)

```bash
# 운영 배포: 이미지 빌드 → 클러스터 안 Deployment로
make docker-build docker-push IMG=<ECR>/website-operator:v0.1.0
make deploy IMG=<ECR>/website-operator:v0.1.0
# config/rbac/의 생성된 Role이 함께 적용됩니다 (마커의 산물)
```

## 정리

```bash
bash cleanup.sh
```
