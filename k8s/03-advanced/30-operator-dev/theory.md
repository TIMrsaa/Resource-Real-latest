# 이론 — controller-runtime의 구조와 Reconcile 설계

> **🌱 17세 눈높이 비유: 자동 온실 관리기 만들기**
> "토마토 온실" 주문서(CRD)를 받으면 — 온도/습도/조명(자식 리소스)을 맞춰주는 관리기(컨트롤러)를 만듭니다.
> 관리기의 핵심 코드는 단 하나의 함수입니다: **"지금 온실 상태를 보고, 주문서와 다르면 맞춥니다."**
> 센서 배선, 알림 큐, 중복 호출 방지... 같은 공통 부품은 **키트(kubebuilder)** 가 다 들어 있습니다 — 우리는 "맞추는 로직"만 씁니다.

---

## 1. 전체 구조

```
controller-runtime Manager
 ├─ 캐시 (informer 묶음 — 모듈 31): watch로 받은 객체들의 로컬 사본
 ├─ Controller: workqueue + 워커
 │    └─ 우리의 Reconcile(ctx, Request{Namespace, Name}) 호출
 ├─ Client: 캐시 우선 읽기 + API 쓰기 (Get/List/Create/Update/Patch)
 └─ 리더 선출 / 메트릭 / 웹훅 서버 (옵션)
```

Request에는 **이름뿐**입니다 — "뭐가 바뀌었는지"는 안 줍니다. 의도된 설계: 이벤트 기반으로 짜면 놓친 이벤트 = 영구 불일치, 상태 기반으로 짜면 어떤 경로로 호출돼도 수렴합니다.

## 2. API 타입 — Go struct가 곧 CRD

```go
// api/v1/website_types.go
type WebsiteSpec struct {
    // +kubebuilder:validation:Pattern=`^.+:.+$`
    Image    string `json:"image"`
    // +kubebuilder:validation:Minimum=1
    // +kubebuilder:validation:Maximum=10
    Replicas int32  `json:"replicas"`
    Domain   string `json:"domain,omitempty"`
}
type WebsiteStatus struct {
    ReadyReplicas int32  `json:"readyReplicas,omitempty"`
    Phase         string `json:"phase,omitempty"`
}
// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:printcolumn:name="Ready",type=integer,JSONPath=`.status.readyReplicas`
type Website struct { ... }
```

`make manifests`가 이 struct와 마커에서 **모듈 24에서 손으로 쓴 그 CRD YAML**을 생성합니다 — 검증/서브리소스/컬럼까지. 타입과 스키마의 단일 진실이 Go 코드가 되는 것.

## 3. Reconcile — 표준 골격

```go
func (r *WebsiteReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
    // 1. 대상 읽기 (캐시에서)
    var site platformv1.Website
    if err := r.Get(ctx, req.NamespacedName, &site); err != nil {
        return ctrl.Result{}, client.IgnoreNotFound(err)   // 삭제됐으면 조용히 종료 (GC가 자식 처리)
    }
    // 2. (외부 자원이 있다면) finalizer 처리 — 삭제 중이면 정리 후 finalizer 제거
    // 3. 원하는 자식 상태 계산 → 생성/갱신
    deploy := r.desiredDeployment(&site)
    ctrl.SetControllerReference(&site, deploy, r.Scheme)    // ownerReference! (모듈 24)
    if err := r.Patch(ctx, deploy, client.Apply,            // Server-Side Apply! (모듈 24)
        client.FieldOwner("website-controller"), client.ForceOwnership); err != nil {
        return ctrl.Result{}, err                            // 에러 반환 = 자동 재시도(백오프)
    }
    // 4. status 보고 (서브리소스로!)
    site.Status.ReadyReplicas = /* 자식 Deployment에서 읽은 값 */
    if err := r.Status().Update(ctx, &site); err != nil { return ctrl.Result{}, err }
    return ctrl.Result{}, nil        // 또는 {RequeueAfter: time.Minute} — 주기 점검
}
```

### 반환값의 의미 (재시도 제어)

| 반환 | 효과 |
|------|------|
| `{}, nil` | 완료 — 다음 이벤트까지 대기 |
| `{}, err` | **자동 재시도** (지수 백오프) — 일시 오류는 그냥 err 반환이 정답 |
| `{RequeueAfter: d}, nil` | d 후 재호출 — 외부 상태 주기 점검용 |

### Watch 배선 — 자식의 변화도 나를 깨웁니다

```go
ctrl.NewControllerManagedBy(mgr).
    For(&platformv1.Website{}).        // 주 대상
    Owns(&appsv1.Deployment{}).        // 내가 만든 자식 — 자식이 바뀌어도 부모 reconcile!
    Complete(r)
```

`Owns` 덕분에 누가 자식 Deployment를 지워도 → 부모 reconcile 호출 → 재생성. **자가 치유가 배선 한 줄.**

## 4. RBAC 마커 — 권한도 코드 옆에

```go
// +kubebuilder:rbac:groups=platform.example.com,resources=websites,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=platform.example.com,resources=websites/status,verbs=update;patch
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
```

`make manifests`가 Role YAML 생성 — 코드가 쓰는 권한과 선언이 어긋나지 않습니다 (모듈 11 최소 권한의 자동화).

## 5. 설계 수칙 (운영 품질의 분수령)

1. **멱등**: Create가 아니라 SSA Patch — 이미 있으면 수렴, 없으면 생성
2. **읽기는 캐시**: r.Get은 캐시다 — 방금 쓴 것이 바로 안 보일 수 있습니다(eventually consistent). "쓰고 바로 읽기" 의존 금지
3. **status는 Status() 채널로**: spec 채널과 섞으면 conflict 지옥 (모듈 24)
4. **에러는 포장해서 위로**: 직접 재시도 루프 금지 — 반환만 하면 백오프는 프레임워크 몫
5. **이벤트 기록**: `r.Recorder.Event(...)` — 사용자가 describe로 보는 그 이벤트(모듈 02)를 우리도 남깁니다

## 6. 소스코드에서 확인하기

- controller-runtime: https://github.com/kubernetes-sigs/controller-runtime — `pkg/internal/controller/controller.go`의 워커 루프 (workqueue에서 꺼내 Reconcile 호출)
- kubebuilder book (사실상의 교과서): https://book.kubebuilder.io
- 실전 표본: https://github.com/cloudnative-pg/cloudnative-pg — PostgreSQL 운영 지식이 코드가 된 모습

## 요약 카드

| 질문 | 답 |
|------|----|
| Reconcile의 입력? | 이름(Request)뿐 — "전체 상태 보고 수렴" 설계 |
| 자식 생성의 표준? | desired 계산 → SetControllerReference → SSA Patch |
| 자식 삭제에도 부활하는 이유? | Owns() 배선 → 자식 변화가 부모 reconcile 유발 |
| 일시 오류 처리? | 그냥 err 반환 — 프레임워크가 백오프 재시도 |
| CRD YAML의 출처? | Go struct + 마커 (`make manifests`) |
