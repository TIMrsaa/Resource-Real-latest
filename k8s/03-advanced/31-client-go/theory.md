# 이론 — client-go: 클라이언트, informer, workqueue

> **🌱 17세 눈높이 비유: 도서관 신간 알림 시스템을 직접 만들기**
> 매번 도서관(API 서버)에 전화해 "신간 있어요?"라고 묻는 건 민폐입니다(폴링). 제대로 된 방법:
> ① 처음 한 번 **전체 목록**을 받아 적고(List) ② 이후엔 **변경 알림 구독**(Watch)
> ③ 내 공책(Indexer 캐시)에 항상 최신 상태 유지 ④ 알림이 오면 **할 일 메모지에 책 제목만**(workqueue에 키만) 적고 ⑤ 한가할 때 메모지를 꺼내 공책을 보며 처리.
> 같은 책 알림이 연달아 5번 와도 메모지엔 **한 장**(중복 제거), 처리 실패한 메모는 점점 뒤로 미룹니다(rate limit 백오프).

---

## 1. 클라이언트 4종

| 클라이언트 | 타입 | 용도 |
|-----------|------|------|
| **clientset** | 정적 타입 (`*v1.Pod`) | 내장 리소스 — 컴파일 타임 안전, 가장 흔함 |
| **dynamic** | `unstructured.Unstructured` (map) | CRD 등 임의 리소스 — 타입 없이 (kubectl이 이것) |
| **discovery** | 메타 정보 | "이 클러스터에 어떤 리소스/버전이 있나" (api-resources의 구현) |
| RESTClient | 원시 HTTP | 위 셋의 토대 — 직접 쓸 일은 드묾 |

```go
cfg, _ := clientcmd.BuildConfigFromFlags("", kubeconfig)   // 밖에서 (Pod 안이라면 rest.InClusterConfig())
cs, _ := kubernetes.NewForConfig(cfg)
pods, _ := cs.CoreV1().Pods("default").List(ctx, metav1.ListOptions{LabelSelector: "app=web"})
```

> InClusterConfig의 재료 = 모듈 11에서 본 그것: 자동 마운트된 SA 토큰 + `kubernetes.default.svc`. 우리가 wget으로 했던 일의 라이브러리판.

## 2. Informer 파이프라인 — 부품별 책임

### Reflector — List+Watch 실행자
- 시작 시 List(전체 + resourceVersion 확보) → 그 rv부터 Watch
- 연결이 끊기면 마지막 rv부터 재개, **410 Gone이면 relist** (모듈 21/22의 compaction!)

### DeltaFIFO — 변경의 순서 보존 버퍼
Reflector와 캐시 사이의 큐. 같은 객체의 연속 변경을 델타 목록으로 압축.

### Indexer — 로컬 캐시 + 색인
- 스레드 안전 저장소. 기본 색인은 namespace
- `GetByKey("ns/name")` — 컨트롤러 읽기의 99%가 여기서 (API 호출 0!)

### SharedInformerFactory — 공유의 미덕
한 프로세스에서 같은 리소스를 보는 컨트롤러가 여럿이어도 **watch는 1개** (factory가 공유). 모듈 21의 "API 서버가 etcd watch를 공유"와 같은 패턴이 클라이언트 쪽에서 반복.

### resync — 주기적 전체 재통보
설정한 주기(예: 10h)마다 캐시의 **모든 객체를 Update 핸들러로 재전달** (API 재조회 아님!). 용도: 핸들러 버그/누락 이벤트의 자기 치유. "resync = relist"로 오해하지 말 것.

## 3. Workqueue — 컨트롤러의 심장 박동기

```go
queue := workqueue.NewTypedRateLimitingQueue(workqueue.DefaultTypedControllerRateLimiter[string]())
// 핸들러에서: queue.Add(key)
// 워커에서:
key, shutdown := queue.Get()
defer queue.Done(key)
if err := process(key); err != nil {
    queue.AddRateLimited(key)      // 실패 → 백오프 재시도 (5ms→10ms→...→1000s)
} else {
    queue.Forget(key)              // 성공 → 백오프 카운터 리셋
}
```

3대 보장:
1. **중복 압축**: 처리 대기 중 같은 키 Add는 1번으로
2. **동시 처리 배제**: 같은 키를 두 워커가 동시에 잡지 않음 (다른 키는 병렬)
3. **rate limit**: 키별 지수 백오프 + 전체 토큰 버킷

→ 모듈 30 Reconcile의 "에러 반환 = 자동 재시도", "이름만 입력" 의 구현 실체가 전부 여기입니다.

## 4. 쓰기의 디테일

```go
// 409 Conflict 표준 대응 (모듈 21의 낙관적 동시성)
retry.RetryOnConflict(retry.DefaultRetry, func() error {
    current, err := cs.AppsV1().Deployments(ns).Get(ctx, name, metav1.GetOptions{})
    if err != nil { return err }
    current.Spec.Replicas = ptr.To(int32(5))
    _, err = cs.AppsV1().Deployments(ns).Update(ctx, current, metav1.UpdateOptions{})
    return err
})
// 또는 SSA (필드 소유권 — 모듈 24): cs.AppsV1().Deployments(ns).Apply(ctx, applyConfig, ...)
```

## 5. 소스코드에서 확인하기 (기여자 트랙 직결)

- client-go: `staging/src/k8s.io/client-go/tools/cache/` — reflector.go, delta_fifo.go, shared_informer.go: 위 부품들이 파일명 그대로
- workqueue: `staging/src/k8s.io/client-go/util/workqueue/`
- **내장 컨트롤러의 표본**: `pkg/controller/replicaset/replica_set.go` — informer 핸들러→큐→syncReplicaSet 워커. 이 모듈을 마치면 이 파일이 "읽히는" 것을 확인해보세요 (모듈 42의 예습)

## 요약 카드

| 질문 | 답 |
|------|----|
| CRD를 타입 없이 다루는 클라이언트? | dynamic (Unstructured) |
| 컨트롤러 읽기의 출처? | Indexer 캐시 (API 호출 아님) |
| 큐에 객체가 아닌 키를 넣는 이유? | 중복 압축 + 낡은 사본 방지 (처리 시점에 캐시에서 최신을) |
| 실패 재시도의 구현? | AddRateLimited (키별 지수 백오프) / 성공 시 Forget |
| resync의 정체? | 캐시 재통보 (relist 아님) — 핸들러 자기 치유 |
| 410 Gone 시 Reflector는? | relist (전체 List부터 다시) |
