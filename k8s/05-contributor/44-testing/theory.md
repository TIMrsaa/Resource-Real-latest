# 이론 — 테스트 3층, K8s 테스트 문법, prow

> **🌱 17세 눈높이 비유: 신약 개발의 3상 시험**
> 새 약(코드 변경)은 바로 사람에게 안 씁니다:
> - **세포 실험(unit)**: 시험관에서 빠르게 수천 번 — 싸고 빨라서 여기서 대부분 걸러냅니다
> - **동물 실험(integration)**: 살아있는 시스템 일부에서 — 상호작용 확인
> - **임상(e2e)**: 진짜 환경에서 끝까지 — 비싸서 마지막에, 핵심 시나리오만
> 그리고 **식약처 심사(prow/CI)**: 어떤 약도 심사 통과 없이 출시(머지) 불가 — 심사 서류 양식(/retest, 라벨)을 알아야 절차가 돕니다.

---

## 1. 3층의 실체 — 무엇이 진짜고 무엇이 가짜인가

| 층 | API서버 | etcd | 노드/kubelet | 위치 | 실행 시간 |
|----|---------|------|--------------|------|----------|
| unit | fake (메모리) | 없음 | 없음 | 각 패키지의 `*_test.go` | 초 |
| integration | **진짜** | **진짜** | 없음(가짜) | `test/integration/` | 분 |
| e2e | 진짜 | 진짜 | **진짜** (kind 등) | `test/e2e/` | 수십 분+ |

층이 올라갈수록 "진짜"가 늘고 비용도 늡니다 — **버그를 잡을 수 있는 가장 낮은 층에서 잡는 것**이 원칙.

## 2. unit — K8s 단위 테스트의 문법 2가지

### ① table-driven (표 주도) — K8s의 표준 양식

```go
func TestMaxSurge(t *testing.T) {
    tests := []struct {
        name       string          // 케이스 이름 (실패 시 표시)
        deployment apps.Deployment // 입력
        expected   int32           // 기대값
    }{
        {name: "percent", deployment: deploymentWith("25%"), expected: 2},
        {name: "absolute", deployment: deploymentWith("3"), expected: 3},
        {name: "zero", deployment: deploymentWith("0"), expected: 0},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got := MaxSurge(tt.deployment)
            if got != tt.expected {
                t.Errorf("got %d, want %d", got, tt.expected)
            }
        })
    }
}
```

케이스 추가 = 표에 한 줄. **버그 수정 PR의 정석이 바로 이것**: 표에 "버그를 재현하는 한 줄"을 추가(→ 실패 확인) → 코드 수정(→ 통과). 리뷰어가 가장 사랑하는 모양.

### ② fake client — 클러스터 없는 컨트롤러 테스트

```go
import "k8s.io/client-go/kubernetes/fake"

client := fake.NewSimpleClientset(pod1, deploy1)  // 메모리 속 가짜 클러스터 + 초기 객체
// 컨트롤러 로직 실행 후:
actions := client.Actions()                        // 어떤 API 호출을 했는지 검증
```

모듈 31에서 진짜 클러스터로 한 일을 메모리에서 — informer/lister까지 fake로 묶는 헬퍼들이 각 컨트롤러 테스트에 이미 있습니다(모방 대상).

## 3. integration — 진짜 API 서버, 가짜 노드

`test/integration/`은 테스트 안에서 **실제 etcd + API 서버 프로세스를 띄웁니다**:

- 검증 대상: admission 체인, GC 동작, 컨트롤러-API 상호작용 등 "fake로는 못 보는 것"
- 요구사항: etcd 바이너리 (`hack/install-etcd.sh` — 모듈 41 lab-02에서 설치함)
- 실행: `make test-integration WHAT=./test/integration/deployment` 처럼 좁혀서

unit과의 결정적 차이: fake client는 admission/검증을 **건너뜁니다** — "API 서버가 실제로 거부하는가"는 integration부터 보입니다.

## 4. e2e — ginkgo와 진짜 클러스터

`test/e2e/`는 ginkgo 프레임워크(BDD 스타일)로, 진짜 클러스터에 사용자처럼 리소스를 만들고 결과를 관찰합니다:

```
[기능 라벨 체계]
[Conformance]   모든 인증 K8s 배포판이 통과해야 하는 핵심 (EKS도 이걸 통과한 것)
[Serial]        다른 테스트와 동시 실행 불가 (노드를 만지는 등)
[Disruptive]    클러스터를 부수는 것
```

로컬 실행은 kind + `hack/ginkgo-e2e.sh` 또는 kubetest2 — 무겁습니다. **입문 기여자는 "CI가 돌려주는 것을 읽을 줄 알면" 충분**합니다.

## 5. prow — PR을 지키는 CI의 언어

PR을 올리면 prow(K8s 자체 CI 시스템)가 작동합니다. 알아야 할 어휘:

| 표시/명령 | 의미 |
|----------|------|
| `k8s-ci-robot`의 코멘트 | prow의 봇 — 라벨/검사 결과를 답니다 |
| pull-kubernetes-unit 등 | PR마다 도는 잡들 (unit/verify/e2e 일부) |
| `/retest` | 실패한 잡 재실행 (flaky일 때) — **남발 금지, 원인 먼저** |
| `/ok-to-test` | 외부인 첫 PR의 CI 실행 승인 (멤버가 해줌) |
| `needs-rebase` 라벨 | upstream과 충돌 — rebase 필요 |
| testgrid.k8s.io | 잡들의 역사적 성적표 — "원래 flaky한 테스트"인지 확인 |

### flake — 현실의 골칫거리

가끔 실패하는 테스트(타이밍/자원 경합). 내 PR과 무관한 실패처럼 보이면: ① 실패 로그에서 내 변경 관련성 확인 ② testgrid에서 그 테스트의 평소 성적 확인 ③ 무관 확신 시 `/retest` + (반복되면) flake 이슈 검색/보고. **"일단 /retest 연타"는 CI 자원 낭비 + 평판 하락.**

## 6. 작업 순서 — 버그 수정의 정석 루프

```
1. 버그를 재현하는 테스트 추가     (table에 한 줄) → go test → FAIL 확인 ★
2. 코드 수정                                        → go test → PASS
3. 그 패키지 전체 테스트                              → 회귀 없음 확인
4. make verify (포맷/생성물/lint)                     → PR 전 필수
5. (영향 크면) 관련 integration 실행
```

1번이 핵심입니다 — **고치기 전에 실패를 봅니다.** 실패를 본 적 없는 테스트는 "버그가 고쳐졌음"을 증명하지 못합니다(원래부터 통과했을 수도).

## 7. 소스/도구에서 확인하기

- 테스트 가이드: kubernetes/community의 contributors/devel/sig-testing/
- testgrid: https://testgrid.k8s.io / prow 상태: https://prow.k8s.io
- ginkgo: https://onsi.github.io/ginkgo/

## 요약 카드

| 질문 | 답 |
|------|----|
| 3층의 구분 기준? | 무엇이 진짜인가 (fake → +API서버/etcd → +노드) |
| unit의 2대 문법? | table-driven + fake client |
| fake client의 맹점? | admission/검증을 건너뜀 → integration의 존재 이유 |
| 버그 수정의 첫 단계? | 실패하는 테스트 먼저 (FAIL을 봅니다) |
| PR 전 필수 명령? | 패키지 테스트 + `make verify` |
| /retest의 예절? | 원인/관련성/testgrid 확인 후 — 연타 금지 |
