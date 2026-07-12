# 자가 점검 퀴즈

**Q1.** 코어(kubernetes-sigs/karpenter)와 프로바이더(aws/karpenter-provider-aws)의 판정 규칙은? 예시 두 개로 보여라.

**Q2.** 두 저장소를 잇는 계약의 이름과, 그 인터페이스의 대표 메서드 3개는?

**Q3.** provisioning 파이프라인에서 Fleet에 넘겨지는 것이 "타입 하나"가 아니라 "타입 집합"인 이유와, 그것이 17의 어떤 조언을 설명하는가요?

**Q4.** 코어 테스트가 AWS 없이 초 단위로 도는 비결은?

**Q5.** 로컬 개발 시 `replace` 지시자의 용도와 그것이 만드는 사고, 예방책은?

**Q6.** 로컬 컨트롤러 실행 전 반드시 해야 할 조치와 그 이유는?

**Q7.** 버그픽스 PR의 커밋 순서는 어떻게 되어야 하며, 왜인가요?

**Q8.** Karpenter의 서명 방식은? kubernetes/kubernetes와 무엇이 다른가?

---

## 정답

**A1.** "다른 클라우드에서도 의미가 있는가요?" → 예면 코어, 아니면 프로바이더. 예: consolidation 알고리즘·스케줄링 시뮬레이터 = **코어**. spot 가격 캐시 갱신, EC2NodeClass의 AMI selector, IMDS hop limit 설정 = **프로바이더**.

**A2.** `CloudProvider` 인터페이스. 대표 메서드: `Create()`(NodeClaim → 실제 인스턴스), `GetInstanceTypes()`(후보 카탈로그+가격+오퍼링), `IsDrifted()`(선언≠실물 감지 — 21의 drift 파도). (외 Delete/Get/List)

**A3.** scheduler.Solve가 Pod 요구 ∩ NodePool requirements를 교집합해 **만족 가능한 타입들의 집합**을 만들고, 그 집합째 EC2 Fleet에 넘겨 AWS가 가격·가용성으로 낙찰합니다. 그래서 requirements를 넓게 열수록 후보 집합이 커져 더 싸고 안정적입니다 — 17의 "네거티브 설계"(배제만 하고 열어둬라) 조언의 코드 수준 근거.

**A4.** ginkgo/gomega + **fake client**(가짜 k8s API)와 **fake CloudProvider**(`pkg/cloudprovider/fake/`) — 실제 클러스터도 AWS도 필요 없이 컨트롤러 로직만 검증합니다. (k8s 44에서 배운 테이블 드리븐/fake client 패턴의 실전)

**A5.** 용도: `go mod edit -replace sigs.k8s.io/karpenter=../core`로 로컬 코어를 가리켜 "코어를 고치며 AWS 프로바이더로 실험". 사고: 그 상태의 go.mod가 PR에 섞이면 CI가 깨지거나 머지 시 릴리스를 손상. 예방: PR 전 `git diff origin/main -- go.mod go.sum` 확인, pre-commit 훅.

**A6.** 클러스터에 설치된 Karpenter Deployment를 `replicas=0`으로. 이유: 두 컨트롤러가 같은 Pending Pod를 보고 각자 NodeClaim을 생성해 **노드 이중 생성**과 consolidation 충돌이 발생합니다(그리고 비용).

**A7.** ① 그 버그를 재현하는 **실패하는 테스트** → ② 그것을 통과시키는 수정. 이유: 리뷰어가 버그의 존재와 수정의 유효성을 코드로 확인할 수 있고, 회귀 방지가 영구히 보장됩니다. 테스트 없는 픽스는 대개 "테스트 추가해 주세요"로 되돌아옵니다.

**A8.** **DCO**(`git commit -s` — Developer Certificate of Origin). kubernetes/kubernetes는 CNCF **CLA** 서명을 요구하는 반면, kubernetes-sigs 계열의 Karpenter는 DCO 방식입니다 — 커밋마다 `Signed-off-by` 라인이 필요합니다.
