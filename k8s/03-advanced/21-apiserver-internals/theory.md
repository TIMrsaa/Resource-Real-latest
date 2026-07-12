# 이론 — 요청의 일생: API 서버 파이프라인 해부

> **🌱 17세 눈높이 비유: 시청 민원 처리 창구**
> 민원서(요청)가 접수되면: **신분증 확인**(인증) → **이 민원을 낼 자격이 있는지**(인가) → **서식 규정 심사 + 직권 수정**(admission: "주소가 빠졌네요, 표준 양식으로 고쳐드렸습니다") → **내용 검증** → **공문서 보관소에 등록**(etcd) → 등록 사실을 **구독 중인 부서들에 통보**(watch).
> 창구가 미어터지면? 민원 종류별 **전용 줄**(APF)이 있어서 "긴급 민원 줄"은 일반 민원 폭주에 밀리지 않습니다.

---

## 1. 전체 파이프라인

```
HTTP 요청 (kubectl/컨트롤러/kubelet — 전부 동일 경로!)
  │
  ▼ ① 인증 (Authentication)         "누구냐" — 실패 시 401
  ▼ ② 인가 (Authorization/RBAC)     "권한 있냐" — 실패 시 403
  ▼ ③ Admission: Mutating           "규정대로 고쳐주마" — 기본값 주입, 사이드카 주입(웹훅)
  ▼ ④ 스키마 검증 + CEL 검증          "양식이 맞냐" — OpenAPI 스키마, ValidatingAdmissionPolicy
  ▼ ⑤ Admission: Validating         "규정 위반이냐" — 거부 가능, 수정 불가
  ▼ ⑥ etcd 저장                      resourceVersion 발급
  │
  └─▶ ⑦ watch 통보: 이 리소스를 구독하는 모두에게 이벤트 스트림
```

순서가 시험 포인트: **Mutating이 Validating보다 먼저** (고친 결과를 검증해야 하므로). 이미 만난 사례로 좌표 찍기:

| 경험했던 것 | 파이프라인 위치 |
|------------|----------------|
| 401 Unauthorized (모듈 11) | ① |
| 403 Forbidden (모듈 11) | ② |
| LimitRange 기본값 주입 (모듈 09) | ③ |
| `replicas: "three"` 거부 | ④ |
| ResourceQuota 초과 거부 (모듈 09) | ⑤ |
| `kubectl get -w` (모듈 02) | ⑦ |

## 2. etcd 저장과 resourceVersion

모든 객체에는 `metadata.resourceVersion`이 있습니다 — etcd의 수정 카운터(revision)에서 온 값. 두 가지 용도:

### ① 낙관적 동시성 제어 (Optimistic Concurrency)

```
A가 객체 읽음 (rv=100) ──┐
B가 객체 읽음 (rv=100) ──┤
B가 수정 제출 (rv=100) ──┼─▶ 성공, 객체는 rv=101
A가 수정 제출 (rv=100) ──┴─▶ ❌ 409 Conflict! "the object has been modified"
```

잠금(lock) 없이 동시 수정을 안전하게 — 실패한 쪽이 **다시 읽고 재시도**하는 것이 규약입니다. `kubectl edit` 중에 컨트롤러가 먼저 고치면 만나는 그 에러. client-go의 `RetryOnConflict`(모듈 31)가 이 재시도의 표준 구현.

### ② watch 시작점

"rv=100 이후의 변화만 보내줘" — 끊겼다 재연결할 때 놓친 것부터 이어받는 메커니즘. 너무 오래 끊겨 etcd가 그 이력을 압축(compaction)해 버렸으면 `410 Gone` → 전체 다시 목록(relist). informer(모듈 31)의 List+Watch 패턴이 이것.

## 3. watch — K8s 실시간성의 전부

```
GET /api/v1/pods?watch=true&resourceVersion=100
→ HTTP 응답이 안 끝나고 계속 흐릅니다 (chunked):
  {"type":"ADDED","object":{...}}
  {"type":"MODIFIED","object":{...}}
  {"type":"DELETED","object":{...}}
```

- 스케줄러도 kubelet도 컨트롤러도 전부 이 스트림의 구독자입니다 — "폴링하는 컴포넌트는 없다"
- API 서버는 etcd watch를 **1번만** 걸고, 수천 클라이언트에게 부채질(fan-out)합니다 (watch cache) — etcd를 보호하는 핵심 설계

## 4. API Priority & Fairness (APF)

API 서버가 과부하일 때 "누구 요청부터 버릴까"의 체계. 옛 방식(--max-requests-inflight 단일 한도)은 폭주하는 한 클라이언트가 전체를 굶겼습니다.

```
FlowSchema:           요청을 분류 ("kubelet의 요청" / "시스템 컨트롤러" / "일반 사용자"...)
PriorityLevelConfiguration: 분류별 동시성 예산과 큐
```

```bash
kubectl get flowschemas, prioritylevelconfigurations   # 기본 세트 구경
```

효과: 잘못 짠 컨트롤러가 초당 수천 LIST를 날려도 **kubelet 하트비트나 리더 선출은 전용 예산으로 보호**됩니다 — "API 폭주가 클러스터 전체 마비로 번지지 않게". 클라이언트가 한도에 걸리면 `429 Too Many Requests` + 재시도 안내를 받습니다.

## 5. 감사 로그 (Audit)

"누가 언제 무엇을 했나"의 공식 기록. 단계: RequestReceived → ResponseComplete. 정책으로 수준(None/Metadata/Request/RequestResponse)을 리소스별 지정. **EKS는 정책이 고정**이고, 켜면 CloudWatch Logs로 흐릅니다 — lab-02에서 조회. 보안 사고 조사("누가 그 Secret을 읽었나")의 출발점.

## 6. 그 밖의 내부 부품 (지도만)

| 부품 | 역할 | 어디서 깊게 |
|------|------|-------------|
| Aggregation Layer | 다른 API 서버를 산하로 편입 (metrics.k8s.io가 이것!) | 모듈 24 |
| OpenAPI/discovery | kubectl explain과 클라이언트 코드의 원천 | 모듈 31 |
| Server-Side Apply | 필드 소유권 기반 병합 | 모듈 24 |
| Lease | 리더 선출, 노드 하트비트 | 모듈 25, 26 |

## 7. 소스코드에서 확인하기 (본문 승격)

- 파이프라인 조립: `staging/src/k8s.io/apiserver/pkg/server/config.go` 의 `DefaultBuildHandlerChain` — 인증/인가/APF가 HTTP 미들웨어로 쌓이는 곳. **이 함수 하나가 이 모듈 전체의 코드판**입니다
- admission 체인: `staging/src/k8s.io/apiserver/pkg/admission/chain.go`
- watch cache: `staging/src/k8s.io/apiserver/pkg/storage/cacher/`
- APF: `staging/src/k8s.io/apiserver/pkg/util/flowcontrol/`

## 요약 카드

| 질문 | 답 |
|------|----|
| 파이프라인 순서? | 인증→인가→Mutating→검증→Validating→etcd→watch |
| Mutating이 먼저인 이유? | 고친 결과를 검증해야 하므로 |
| 409 Conflict의 의미? | resourceVersion 불일치 — 다시 읽고 재시도하세요 |
| watch가 etcd를 안 죽이는 이유? | API 서버의 watch cache가 1:N 부채질 |
| 429의 출처? | APF — 분류별 동시성 예산 초과 |
| "누가 Secret 읽었나"? | 감사 로그 (EKS: CloudWatch) |
