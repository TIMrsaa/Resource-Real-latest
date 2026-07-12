# 학습 가이드 — 사용자 지식이 기여 자격이 되는 곳

## 14의 지식이 여기서 이자를 낳습니다

14에서 배운 것들 — refresh와 reconcile의 구분, sync wave, selfHeal/prune의 양날, 필드 소유권 다툼(HPA vs Git) — 은 argo-cd 저장소의 이슈 목록에서 **매일 논쟁되는 주제들**입니다. 사용자로서 겪은 그 함정들이 여기서는 기여 재료가 됩니다: 이슈 재현, 문서 개선, 테스트 케이스 추가, 그리고 코드 수정.

이것이 기여자 트랙의 설계입니다: 사용(14·17) → 운영의 상처(pitfalls) → 소스에서 원인 확인 → 기여. 상처 없이 소스만 읽으면 "어디가 아픈지"를 모르고, 상처만 있고 소스를 안 읽으면 불평만 남습니다.

## 26과의 대비 — 거버넌스가 다르면 전략이 다릅니다

```
26 actions/runner   기업 주도 — 로드맵은 GitHub의 것, 외부 기여는 이슈·진단 중심
27 argoproj         CNCF Graduated 오픈 거버넌스 — 유지보수자가 여러 회사(Intuit·Akuity·Codefresh·RedHat...)
                    proposal 절차 공개, 기여자 미팅 공개, 코드 PR이 실제로 환영받음
28 tektoncd         CDF(Continuous Delivery Foundation) — k8s식 프로세스(OWNERS, /lgtm)의 또 다른 재단
```

오픈 거버넌스의 실질적 의미: **머지의 길이 문서화되어 있고, 특정 회사의 허락이 아니라 절차를 통과하면 됩니다.** 대신 절차가 있다는 것은 절차를 읽어야 한다는 뜻입니다 — proposal이 필요한 변경 크기, 리뷰어/승인자 규칙, 릴리스 주기. k8s 45에서 배운 문법이 거의 그대로 통하는 동네입니다.

## 2저장소 통찰 — gitops-engine이라는 경계

eks 28에서 Karpenter가 코어(중립)/프로바이더(AWS)로 나뉜 것을 봤습니다. argo-cd에도 같은 구조가 있습니다: **diff·sync의 핵심 엔진은 argoproj/gitops-engine**으로 분리되어 있습니다(Flux와의 협력 시도에서 나온 역사적 산물). "sync가 이상해요"의 수정처가 argo-cd일 수도 gitops-engine일 수도 있습니다 — 경계 판정이 기여의 첫 기술이라는 것이 이 트랙의 반복 주제입니다.

## UI라는 특별한 문

argo-cd의 ui/는 React+TypeScript입니다 — Go가 부담스러운 프런트엔드 개발자에게 열린 문이고, UI 이슈는 상대적으로 경쟁이 덜합니다. 18(TS 액션)·26(toolkit)에 이어 "자기 언어의 문으로 들어가라"는 원칙이 여기서도 성립합니다.
