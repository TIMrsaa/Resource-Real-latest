# 이론 — 코드 지도, 컨트롤러의 해부, 기여의 절차

> **🌱 17세 눈높이 비유: 자동차 회사의 두 팀**
> - **코어(kubernetes-sigs/karpenter)** = 자동차의 **설계·주행 로직** 팀: "승객 몇 명, 짐 얼마면 어떤 크기의 차가 필요한가"를 계산합니다. 어느 나라에서 파는지는 모릅니다
> - **프로바이더(aws/karpenter-provider-aws)** = **현지 법인**: "한국에서 파는 차종 목록과 가격표", "현지 공장에 주문 넣는 법"을 압니다
> - 둘은 **계약서(CloudProvider 인터페이스)** 로 연결됩니다 — 코어가 "6인승 이상, 예산 X"라고 하면 법인이 "그럼 이 모델"이라고 답합니다
> - **내 개선이 어느 팀 일인가요?** "짐 계산 공식이 틀렸다" = 코어. "한국 가격표가 오래됐다" = 법인. 문을 틀리면 서류가 회사를 떠돕니다

---

## 1. 저장소 경계와 CloudProvider 계약

```go
// 코어가 정의하고 프로바이더가 구현하는 계약 (개념 축약)
type CloudProvider interface {
    Create(ctx, *NodeClaim) (*NodeClaim, error)         // EC2 Fleet 호출 (프로바이더)
    Delete(ctx, *NodeClaim) error
    Get(ctx, providerID string) (*NodeClaim, error)
    List(ctx) ([]*NodeClaim, error)
    GetInstanceTypes(ctx, *NodePool) ([]*InstanceType, error)  // 후보 카탈로그+가격
    IsDrifted(ctx, *NodeClaim) (DriftReason, error)     // AMI 갱신 감지 등 (21의 그 drift)
}
```

이 인터페이스가 두 세계의 국경입니다. **코어를 읽을 땐 여기서 출발**하세요 — 코어의 모든 로직은 결국 이 함수들을 호출할 뿐이고, 프로바이더의 모든 코드는 이것을 구현할 뿐입니다.

## 2. 코어 코드 지도 (kubernetes-sigs/karpenter)

```
pkg/apis/v1/                     NodePool, NodeClaim CRD 타입 (17에서 쓴 그 YAML의 Go 원본)
pkg/controllers/
  provisioning/                  ★ "Pending → 노드" 파이프라인
    scheduling/                    ★★ 스케줄링 시뮬레이터 (17 theory §2-②의 실체)
      scheduler.go                   Pod들을 가상 노드에 bin-packing
      nodeclaim.go                   가상 노드 = NodeClaim 후보
      topology.go                    topologySpread/affinity 평가
  disruption/                    ★ consolidation·drift·expiration
    consolidation.go               delete/replace 판정 (17 lab-02의 그 동작)
    drift.go                       선언≠실물 감지 (21의 파도)
    budgets.go                     동시 중단 폭 제어
  nodeclaim/                     생애주기(launch→register→initialize→terminate)
pkg/scheduling/                  requirements 대수학 (In/NotIn/Exists의 교집합 연산)
pkg/test/                        테스트 픽스처 (fake client 헬퍼)
```

**읽기 순서 추천**: `pkg/apis/v1`(타입) → `provisioning/scheduling/scheduler.go`(핵심 알고리즘) → `disruption/consolidation.go` → 나머지. 17의 사용자 지식이 각 파일의 나침반이 됩니다.

## 3. 프로바이더 코드 지도 (aws/karpenter-provider-aws)

```
pkg/apis/v1/ec2nodeclass.go      EC2NodeClass 타입 (AMI selector, subnet/SG selector)
pkg/providers/
  instancetype/                  ★ 인스턴스 타입 카탈로그 + 오퍼링(존×capacity-type×가격)
  pricing/                       가격 데이터 (온디맨드/spot) — 갱신 로직
  amifamily/                     AL2023/Bottlerocket/Windows별 부트스트랩·AMI 해석
  launchtemplate/                UserData, IMDS 옵션(25의 hop limit!), 블록 디바이스
  instance/                      EC2 Fleet 호출, 인터럽션 큐(SQS) 처리
pkg/cloudprovider/               ★ CloudProvider 인터페이스 구현부 — 두 세계의 접점
test/suites/                     e2e (실제 AWS에 노드를 만드는 무거운 테스트)
```

## 4. 컨트롤러의 해부 — 하나의 reconcile을 따라가기

Pending Pod가 노드가 되기까지, 코어에서:

```
provisioning.Controller.Reconcile()
 ├ 1. Pending Pod 수집 (스케줄 실패한 것들)
 ├ 2. cloudProvider.GetInstanceTypes(nodePool)      ← 프로바이더: 후보+가격
 ├ 3. scheduler.Solve(pods, instanceTypes)          ← 코어: 시뮬레이션·bin-packing
 │     - Pod의 requirements ∩ NodePool.requirements ∩ 인스턴스 타입 라벨
 │     - 결과: NodeClaim 후보 목록 (각각 "이 Pod들을 담을 수 있는 타입 집합")
 ├ 4. NodeClaim 생성 (k8s API)
 └ 5. nodeclaim.Controller가 cloudProvider.Create() → EC2 Fleet
```

여기서 얻는 통찰: **타입 하나가 아니라 "타입 집합"을 Fleet에 넘깁니다** — 그래서 requirements를 넓게 쓰면 가격·가용성이 좋아집니다(17 theory §3의 역설이 코드로 설명됩니다). `scheduling.Requirements`의 교집합 연산(`pkg/scheduling/requirements.go`)이 이 집합을 만드는 대수학입니다.

## 5. 테스트 문화

```go
// 코어: ginkgo/gomega + fake client — 클러스터 없이 초 단위 (k8s 44의 그 패턴)
It("should provision a node for a pending pod", func() {
    ExpectApplied(ctx, env.Client, nodePool, pod)
    ExpectProvisioned(ctx, env.Client, cluster, cloudProvider, prov, pod)
    ExpectScheduled(ctx, env.Client, pod)      // Pod가 노드에 바인딩됐는가
})
```

- 단위/통합: `make test` — PR의 필수 관문. **버그픽스 PR은 "그 버그를 재현하는 테스트"를 반드시 포함**합니다(테스트가 없으면 회귀를 막지 못합니다)
- e2e: `test/suites/` — 실제 AWS 리소스 생성, CI에서만(비용). 로컬에서 함부로 돌리지 말 것
- fake CloudProvider: 코어 테스트가 AWS 없이 도는 비결 — `pkg/cloudprovider/fake/`

## 6. 기여 절차 (k8s 45의 문법이 여기서도)

```
1. good-first-issue 검색 → 이슈에 "/assign" 또는 댓글로 의사 표명 (중복 작업 방지)
2. fork → 브랜치 → 변경 + 테스트
3. make presubmit (또는 make verify test) — 로컬에서 CI를 미리 통과
4. PR 생성: 제목은 명령형("fix: ...", "feat: ..."), 본문에 Fixes #123
5. CI 통과 → 리뷰어 지정(자동) → 피드백 반영 (force-push 대신 커밋 추가 후 스쿼시는 머지 시)
6. `lgtm` + `approved` 라벨 → 자동 머지 (prow — k8s와 같은 봇 문화)
```

DCO(Developer Certificate of Origin) 서명 필요: `git commit -s`. CLA가 아니라 DCO라는 점이 kubernetes-sigs 계열의 특징.

## 7. 좋은 첫 기여 후보

| 유형 | 예 | 난이도 |
|------|----|--------|
| 문서 | NodePool 필드 설명 보강 | ★ |
| 테스트 | 커버되지 않은 엣지 케이스 추가 | ★★ |
| 관측성 | 유용한 로그·이벤트·메트릭 추가 (예: "왜 이 타입을 골랐나") | ★★ |
| 버그픽스 | good-first-issue 라벨의 재현 가능한 버그 | ★★★ |
| 기능 | 새 필드·정책 — **먼저 이슈로 설계 합의**(RFC 문화) | ★★★★ |

## 8. 소스/도구에서 확인하기

- 코어: https://github.com/kubernetes-sigs/karpenter (CONTRIBUTING.md, `pkg/controllers/provisioning/scheduling/`)
- 프로바이더: https://github.com/aws/karpenter-provider-aws (`pkg/providers/instancetype/`)
- Karpenter 워킹그룹 미팅(공개) — 설계 논의를 듣는 것이 최고의 학습
- k8s 43(KEP/SIG)의 문법: Karpenter는 SIG-Autoscaling 산하

## 요약 카드

| 질문 | 답 |
|------|----|
| 저장소 판정 규칙? | "다른 클라우드에서도 의미 있는가" → 코어 / 아니면 프로바이더 |
| 두 세계의 계약? | CloudProvider 인터페이스 (Create/GetInstanceTypes/IsDrifted…) |
| 핵심 알고리즘 위치? | 코어 `provisioning/scheduling/scheduler.go` |
| Fleet에 넘기는 것? | 타입 하나가 아니라 **타입 집합** — 넓은 requirements가 유리한 이유 |
| 버그픽스 PR의 필수품? | 그 버그를 재현하는 **테스트** |
| 서명? | DCO (`git commit -s`) — CLA 아님 |
| 첫 기여 추천? | 문서 → 테스트 → 관측성 로그 → 버그픽스 |
