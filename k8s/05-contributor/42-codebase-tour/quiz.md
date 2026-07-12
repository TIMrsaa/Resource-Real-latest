# 자가 점검 퀴즈

**Q1.** 코드 읽기 전술 3종과 각각이 강한 상황은?

**Q2.** kubectl get의 테이블 출력에 관한 반전과 그 증거(어디서 확인)는?

**Q3.** "Pod의 어떤 필드가 왜 수정 불가인지"를 코드에서 확인하는 위치 공식은?

**Q4.** Deployment 컨트롤러가 Pod를 직접 만들지 않습니다 — 코드 구조상 근거와 설계 원칙은?

**Q5.** 스케줄러에서 schedulingCycle은 직렬, bindingCycle은 고루틴 — 코드의 어느 파일에서 확인했고 이유는?

**Q6.** 새로 보는 컨트롤러 패키지를 여는 순서(추천 3단계)는?

**Q7.** OWNERS 파일에서 읽을 수 있는 것 3가지와 그것이 45(첫 PR)에 주는 의미는?

**Q8.** "이 코드 줄이 왜 생겼는지"를 알아내는 git 고고학 절차는?

---

## 정답

**A1.** ① 문자열 입구(에러/로그 문구 grep) — 운영 증상에서 코드로 들어갈 때. ② 인터페이스 추적(정의→구현체) — 구조/확장점을 파악할 때. ③ 테스트 읽기 — 함수의 보장(명세)을 알고 싶을 때.

**A2.** 테이블 렌더링은 클라이언트가 아니라 **API 서버**가 합니다 — kubectl이 `Accept: ...;as=Table`로 협상하고 서버가 열 정의까지 내려줍니다. 증거: get.go의 빌더/Accept 설정 + `kubectl get -v=8`의 요청 헤더.

**A3.** `pkg/registry/<group>/<kind>/strategy.go` — PrepareForCreate/PrepareForUpdate/Validate가 그 리소스의 생성/수정 규칙의 원문입니다.

**A4.** deployment 패키지의 rolling.go는 **ReplicaSet의 replicas 숫자만** 조정합니다 — Pod 생성은 ReplicaSet 컨트롤러의 몫. 원칙: 컨트롤러는 자기 바로 아래 단계 리소스만 책임집니다(계층 위임) — 그래서 각 컨트롤러가 작고 조합 가능합니다.

**A5.** `pkg/scheduler/schedule_one.go` — 스케줄링은 노드 자원의 일관된 계산을 위해 직렬(한 번에 한 Pod), 바인딩은 API 왕복이라 느려서 `go func()`로 병렬 + assume(캐시 선반영)으로 다음 스케줄링이 안 기다리게 (모듈 25 이론의 원문).

**A6.** ① `<이름>_controller.go`에서 informer 핸들러/큐 배관 확인(모듈 31 골격과 대조) ② `sync<Kind>` 함수의 분기 골격 훑기 ③ 질문 관련 분기만 정독 + `_test.go`로 명세 확인.

**A7.** ① approvers(머지 권한자) ② reviewers ③ `labels: sig/xxx`(주인 SIG). 의미: 내 PR을 누가 리뷰/승인할지, 어느 SIG 채널에 질문할지, 이슈에 어떤 라벨이 붙을지가 전부 여기서 결정됩니다.

**A8.** `git log -S "그 문자열" --oneline -- <경로>` → 해당 커밋 메시지에서 PR 번호 → GitHub PR의 논의/링크된 이슈/KEP까지. 추측 대신 결정의 원문을 찾습니다.
