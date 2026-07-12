# 이론 — 코드베이스 지도와 읽기 전술

> **🌱 17세 눈높이 비유: 대도시에서 길 찾기**
> 서울 전체를 외우는 사람은 없습니다 — 능숙한 사람은 **지하철 노선도(컴포넌트 구조) + 검색(grep) + 목적지(질문)** 로 움직입니다. 처음 가는 동네(패키지)여도 "역에서 내려서 큰길 따라"(진입점에서 호출 따라) 가면 도착합니다. 이 모듈은 노선도를 외우게 하는 게 아니라 **길 찾는 법**을 몸에 붙입니다.

---

## 1. 전체 지도 (모듈 41 §1의 확대)

```
cmd/<component>/            진입점: flag 파싱 → 옵션 → Run()
  └─→ pkg/ 또는 staging/    본체

컴포넌트별 본체 위치:
  kube-apiserver    →  pkg/controlplane/, staging/.../apiserver/
  kube-scheduler    →  pkg/scheduler/            (25에서 봄)
  controller-manager→  pkg/controller/<이름>/     (deployment/, job/, ...)
  kubelet           →  pkg/kubelet/              (26에서 봄)
  kube-proxy        →  pkg/proxy/                (28에서 봄)
  kubectl           →  staging/.../kubectl/pkg/cmd/<동사>/
API 타입 정의:
  내장 리소스        →  staging/.../api/<group>/<version>/types.go
  공통 기계장치      →  staging/.../apimachinery/
```

### 모든 컴포넌트의 공통 골격

```go
// cmd/*/main.go 는 거의 다 이 모양:
func main() {
    command := app.NewXxxCommand()   // cobra 명령 구성
    code := cli.Run(command)         // flag → 검증 → Run()
    os.Exit(code)
}
// → app.Run() → 옵션으로 핵심 객체 조립 → 루프 시작 (informer 기동 포함)
```

진입점은 "조립 설명서"다 — 로직이 아니라 **무엇을 조립해 어느 루프를 도는지**를 읽는 곳.

## 2. 읽기 전술 3종 (상세)

### 전술 ① 문자열 입구

```bash
# 운영에서 본 메시지 → 코드 위치
grep -rn "exceeded quota" pkg/ staging/ --include="*.go" | grep -v _test | head
# 이 코드가 언제/왜 생겼나 → 커밋과 PR 번호까지
git log -S "exceeded quota" --oneline -- pkg/ | tail -3
```

에러/이벤트/로그 문구는 **사용자 세계와 코드 세계를 잇는 다리**입니다. 모듈 38에서 읽던 그 메시지들이 전부 입구가 됩니다.

### 전술 ② 인터페이스 추적 (Go 특화)

K8s는 인터페이스로 층을 가릅니다 — 정의를 찾고 구현체를 나열하면 구조가 보입니다:

```bash
# 예: 스케줄러 플러그인 (모듈 25의 그 확장점들)
grep -rn "type FilterPlugin interface" pkg/scheduler/framework/
grep -rln "func.*Filter(ctx" pkg/scheduler/framework/plugins/ | head   # 구현체들
```

에디터에선: 인터페이스 메서드에서 "Go to Implementations" 한 방.

### 전술 ③ 테스트로 이해

```bash
ls pkg/controller/deployment/*_test.go
# 테스트 함수 이름 = 동작 명세서
grep -n "^func Test" pkg/controller/deployment/sync_test.go | head
```

"이 함수가 뭘 보장하지?"의 답은 주석보다 테스트가 정확합니다. 그리고 44에서 **내가 쓸 테스트의 견본**이기도 합니다.

## 3. 소유권 — 이 코드의 주인 찾기

모든 디렉터리에 `OWNERS` 파일이 있습니다:

```bash
cat pkg/scheduler/OWNERS
# approvers/reviewers 목록 + labels: sig/scheduling
```

- `labels: sig/xxx` → 이 코드를 관리하는 SIG (모듈 43의 주제)
- approvers → PR을 머지시킬 수 있는 사람들 — 45에서 내 PR을 리뷰할 사람들입니다
- **버그 리포트/질문/PR 모두 이 소유권을 따라갑니다** — 코드 지도 = 커뮤니티 지도

## 4. 원정 지도 (lab 미리보기)

| 원정 | 질문 | 경로 (요약) |
|------|------|------------|
| ① kubectl get | "한 명령이 어떻게 REST 호출이 되나" | cmd/kubectl → cmd/get/get.go → builder → RESTClient |
| ② API 서버 | "리소스 핸들러는 어떻게 등록되나" | controlplane/instance.go → legacy REST storage → etcd3 store |
| ③ Deployment 컨트롤러 | "롤링 업데이트는 누가 하나" | controller/deployment/ → syncDeployment → rolling.go |
| ④ 스케줄러 | "25의 사이클이 코드로는" | scheduler/schedule_one.go → 프레임워크 → 플러그인 |

## 5. 소스/도구에서 확인하기

- 코드 검색 엔진: https://cs.k8s.io (리포 전체 정규식 검색 — grep보다 빠를 때 많음)
- 컴포넌트 아키텍처 문서: kubernetes/community의 contributors/devel/sig-*/ 디렉터리
- OWNERS 스펙: https://www.kubernetes.dev/docs/guide/owners/

## 요약 카드

| 질문 | 답 |
|------|----|
| 코드 읽기의 출발? | 질문 — 목적지 없는 독해 금지 |
| 가장 빠른 입구? | 에러/로그 문구 grep |
| 구조 파악 도구? | 인터페이스 정의 → 구현체 나열 |
| 동작 명세서? | `*_test.go` |
| 코드의 주인? | 디렉터리의 OWNERS (→ SIG 라벨) |
| 이 변경 왜 생겼지? | `git log -S"문구"` → 커밋 → PR 링크 |
