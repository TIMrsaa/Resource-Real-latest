# 학습 가이드 — 포장을 뜯는 이유

## 왜 바닥까지 내려가나

controller-runtime만 쓰면 되는데 왜 client-go를 배우나:

1. **kubernetes/kubernetes의 내장 컨트롤러들은 전부 client-go 생짜**입니다 — 기여자 트랙(42)에서 RS/Deployment 컨트롤러를 읽으려면 informer/workqueue 어휘가 필수
2. controller-runtime이 이상하게 굴 때(캐시 미스, 핸들러 안 불림) 그 아래에서 무슨 일이 나는지 알아야 디버깅이 됩니다
3. kubectl 플러그인, 운영 자동화 스크립트, 모니터링 수집기 — Reconcile 패턴이 과한 곳에서는 client-go 직접 사용이 더 가볍습니다

## 미리 그리는 지도 (lab-02에서 직접 조립할 것)

```
API 서버
  │ ① List (전체 한 번) + Watch (이후 변경 스트림)     ← 모듈 21의 그 메커니즘
  ▼
Reflector ──▶ DeltaFIFO ──▶ ② Indexer (로컬 캐시: 스레드 안전 저장소)
                   │
                   ▼ ③ 이벤트 핸들러 (Add/Update/Delete)
                       └─▶ ④ Workqueue에 "키"만 넣음 (중복 제거 + 재시도 + rate limit)
                              └─▶ ⑤ 워커: 키를 꺼내 캐시에서 읽고 처리
```

controller-runtime의 Manager/캐시/Reconcile이 정확히 ①~⑤의 포장입니다. 모듈 30에서 "왜 입력이 이름뿐인가"의 답도 여기 있습니다 — **큐에는 키만 들어가니까** (객체를 넣으면 낡은 사본 문제 + 중복 제거 불가).

## 핵심 설계 감각 미리

- **캐시에서 읽고, API에 씁니다** — 읽기를 API로 하면 컨트롤러 수가 곧 API 부하 (모듈 21 pitfall의 informer 버전)
- **큐의 중복 제거**: 같은 키가 처리 전에 10번 들어와도 1번 처리 — "이벤트 폭풍에도 일은 한 번"
- **rate limiter**: 실패한 키는 점점 느리게 재시도 — 모듈 30의 "에러만 반환하면 백오프"의 구현체
