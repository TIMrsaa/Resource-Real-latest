# Lab 01 — 단위 테스트: 읽고, 돌리고, 작성합니다

> `cd ~/go/src/k8s.io/kubernetes` 에서.

## Step 1. 돌려보기 — 가장 작은 단위부터

```bash
# 모듈 42 원정 ③에서 본 deployment util의 테스트만
time go test ./pkg/controller/deployment/util/... | tail -3
# 특정 함수 하나만 (정규식)
go test ./pkg/controller/deployment/util/ -run TestNewRSNewReplicas -v | head -20
```

예상: `ok` + 초 단위 — **빌드 사다리 1단의 속도**를 체감. `-v`는 케이스(표의 행)별 통과를 보여줍니다.

## Step 2. table-driven 정독 — 모방 대상 고르기

```bash
grep -n "tests := \[\]struct\|testCases := \[\]struct" pkg/controller/deployment/util/deployment_util_test.go | head -3
```

에디터로 `TestNewRSNewReplicas`(또는 비슷한 것)를 열고 구조 분석:
- struct 필드 = 입력과 기대값의 스키마
- 표의 각 행 = 하나의 시나리오 (이름이 곧 문서)
- 루프 본문 = 실행과 비교 (전 케이스 공통)

✅ "이 함수의 동작 명세 = 이 표"라는 감각이 들면 통과. 42에서 "읽기"로 쓴 전술 ③이 이제 "쓰기"의 견본이 됩니다.

## Step 3. 직접 작성 ① — 기존 표에 케이스 추가

가장 흔한 기여 형태의 연습. `MaxSurge` 계열 함수의 테스트 표에 경계 케이스 한 줄을 추가해보세요:

```bash
grep -n "func TestMaxSurge\|func TestMaxUnavailable" pkg/controller/deployment/util/deployment_util_test.go
```

추가할 케이스 예 (이미 있다면 다른 경계값으로):
```go
{
    name:       "surge percent rounds up",      // 25%에 replicas 2 → 0.5 → 올림 1?
    deployment: generateDeployment(...),         // 파일 안의 헬퍼를 그대로 사용!
    expected:   ...,
},
```

```bash
go test ./pkg/controller/deployment/util/ -run TestMaxSurge -v
```

✅ 핵심 기술: **파일 안의 기존 헬퍼/팩토리를 재사용**합니다 (직접 객체를 조립하지 않고). 스타일 모방이 곧 리뷰 통과율입니다.

## Step 4. 직접 작성 ② — fake client로 미니 검증

모듈 31의 감각을 K8s 리포 안에서. 아무 곳에나 새 파일을 만들지 말고 **연습용 디렉터리**에서:

```bash
mkdir -p ~/k8s-test-lab && cd ~/k8s-test-lab && go mod init lab
go get k8s.io/client-go@latest k8s.io/api@latest k8s.io/apimachinery@latest
cat > fake_test.go <<'EOF'
package lab

import (
    "context"
    "testing"
    corev1 "k8s.io/api/core/v1"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
    "k8s.io/client-go/kubernetes/fake"
)

func TestPodCounter(t *testing.T) {
    client := fake.NewSimpleClientset(
        &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "a", Namespace: "x"}},
        &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "b", Namespace: "x"}},
    )
    pods, err := client.CoreV1().Pods("x").List(context.TODO(), metav1.ListOptions{})
    if err != nil { t.Fatal(err) }
    if len(pods.Items) != 2 {
        t.Errorf("got %d pods, want 2", len(pods.Items))
    }
    // fake의 진가: 어떤 API 호출이 있었는지 검증 가능
    if got := len(client.Actions()); got != 1 {
        t.Errorf("got %d actions, want 1 (list)", got)
    }
}
EOF
go test -v ./...
```

✅ 클러스터 없이 "클라이언트를 쓰는 코드"가 검증됩니다 — 컨트롤러/operator(모듈 30) 테스트의 원리이자, K8s 본체 컨트롤러 테스트의 골격.

## Step 5. 정석 루프 체험 — 실패를 먼저 봅니다

theory §6의 순서를 인공 버그로 한 바퀴:

```bash
cd ~/go/src/k8s.io/kubernetes
# ① 일부러 버그 주입: MaxSurge 계산에서 +1 (혹은 아무 산수 비틀기)
#    pkg/controller/deployment/util/deployment_util.go 의 해당 함수 수정
go test ./pkg/controller/deployment/util/ -run TestMaxSurge -v | tail -5    # ② FAIL — 표가 잡아냅니다!
git checkout -- pkg/controller/deployment/util/                              # ③ 원복 = "수정"
go test ./pkg/controller/deployment/util/ -run TestMaxSurge | tail -1        # ④ ok
```

✅ 표가 회귀를 잡는 것을 직접 봤습니다 — 거꾸로 말하면, **내가 추가한 표의 한 줄이 미래의 누군가의 버그를 잡습니다.** 그게 테스트 기여의 가치입니다.

## Step 6. PR 전 의식 — make verify 맛보기

```bash
# 전체는 오래 걸리니 대표 검사 두엇만
hack/verify-gofmt.sh && echo FORMAT-OK
# (시간 있으면) make verify 전체 — PR 직전의 필수 의식임을 기억
```

## 정리

`~/k8s-test-lab`은 유지(45에서 재사용 가능), 리포는 `git status`로 깨끗한지 확인.
