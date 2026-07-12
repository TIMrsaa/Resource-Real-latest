# Lab 01 — 원정 ①②: kubectl 명령에서 etcd 문턱까지

> `cd ~/go/src/k8s.io/kubernetes` 에서. 에디터(VS Code 등)로 리포를 열어두고 터미널과 병행하세요.
> **원정의 규칙**: 각 Step의 질문에 먼저 추측으로 답을 적고 → 코드로 확인합니다.

## 원정 ① kubectl get — CLI 한 줄의 해부

### Step 1. 진입점에서 동사까지

```bash
cat cmd/kubectl/kubectl.go                    # main: command 만들고 실행 — 끝
grep -rn "NewCmdGet" staging/src/k8s.io/kubectl/pkg/cmd/cmd.go
ls staging/src/k8s.io/kubectl/pkg/cmd/        # 동사별 디렉터리: get, apply, drain...
```

✅ kubectl = **cobra 명령 트리**. 동사 하나 = 디렉터리 하나. (모듈 35에서 본 drain 로직도 여기 `drain/`에 있습니다 — 확인해보세요)

### Step 2. get.go에서 추적 — 질문: "-o wide는 어디서 처리되나"

```bash
grep -n "wide" staging/src/k8s.io/kubectl/pkg/cmd/get/get.go | head -5
# humanreadable/테이블 변환 쪽으로 이어집니다:
grep -rn "server-side printing\|Table" staging/src/k8s.io/kubectl/pkg/cmd/get/get.go | head -3
```

에디터에서 `get.go`의 `Run` 함수를 열고 따라가라. 발견하게 되는 반전: **테이블 렌더링은 클라이언트가 아니라 API 서버가 합니다** (`application/json;as=Table` 협상 — 서버가 열 정의까지 내려줍니다). `kubectl get -v=8`에서 본 그 Accept 헤더의 정체.

### Step 3. REST 호출이 조립되는 곳

```bash
grep -rn "resource.NewBuilder" staging/src/k8s.io/kubectl/pkg/cmd/get/get.go
```

`Builder` 패턴: 인자("pods", "my-pod")와 flag(-n, -l)를 모아 → RESTClient 요청으로. 모듈 31에서 우리가 손으로 만들던 clientset 호출이, kubectl 안에선 이 빌더로 일반화돼 있습니다.

✅ **원정 ① 보고서**: `kubectl get pods` = cobra 파싱 → Builder가 요청 조립 → GET /api/v1/.../pods (Accept: Table) → 서버가 만든 테이블을 출력. "kubectl은 얇습니다 — 지능은 서버에 있습니다."

## 원정 ② API 서버 — 리소스는 어떻게 "등록"되나

질문: 모듈 21에서 본 "REST 경로마다 핸들러"는 누가 어떻게 만들었나요?

### Step 4. 조립 설명서 읽기

```bash
grep -n "func.*InstallLegacyAPI\|InstallAPIs" pkg/controlplane/instance.go | head
# Pod, Service 등 핵심(legacy) 그룹의 스토리지 조립:
grep -rn "restStorageProviders\|NewLegacyRESTStorage" pkg/controlplane/ | grep -v _test | head -5
```

에디터로 따라가면: 리소스마다 **storage(REST 전략)** 객체를 만들어 경로에 매핑하는 거대한 조립 코드가 나옵니다 — "API 서버 = REST storage들의 묶음"이라는 구조.

### Step 5. Pod 한 종류의 storage 해부

```bash
ls pkg/registry/core/pod/storage/
grep -n "func NewStorage" pkg/registry/core/pod/storage/storage.go | head -2
# 생성/수정 시 검증·기본값은 "전략(strategy)"에:
grep -n "PrepareForCreate\|Validate" pkg/registry/core/pod/strategy.go | head -5
```

✅ 모듈 21의 파이프라인 "검증" 단계의 실체가 이 strategy들입니다. **"Pod의 spec.nodeName은 왜 수정 불가지?"** 같은 질문의 답이 `PrepareForUpdate`에 코드로 적혀 있습니다.

### Step 6. etcd 문턱

```bash
grep -rn "func (s \*store) Create" staging/src/k8s.io/apiserver/pkg/storage/etcd3/store.go | head -1
```

`etcd3/store.go`의 Create/GuaranteedUpdate가 모듈 22에서 본 etcd 트랜잭션(txn)의 호출자입니다 — resourceVersion 충돌(409)이 만들어지는 바로 그 지점도 이 파일에 있습니다 (`OptimisticLockError` 계열을 grep 해보세요).

✅ **원정 ② 보고서**: 요청 → (인증/인가/admission 체인) → 해당 리소스의 REST storage → strategy 검증 → etcd3 store → etcd. 모듈 21의 그림과 1:1 대응.

## 원정 기록 남기기 (산출물)

```markdown
# 코드 원정 노트 ①②
- kubectl get의 테이블은 서버가 만듭니다 (Accept: as=Table) — get.go:NNN
- 동사 추가하려면: staging/.../cmd/<동사>/ + cmd.go 등록
- 리소스 검증 로직 위치 공식: pkg/registry/<group>/<kind>/strategy.go
- 409의 출생지: apiserver/pkg/storage/etcd3/store.go
- 다음에 길 잃으면: 문구 grep → 정의 이동 → 호출자 역추적
```
