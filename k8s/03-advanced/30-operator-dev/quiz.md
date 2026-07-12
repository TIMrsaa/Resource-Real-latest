# 자가 점검 퀴즈

**Q1.** Reconcile의 입력이 "이름뿐"인 설계의 이유는?

**Q2.** 자식 리소스 생성에 Create 대신 SSA Patch를 쓰는 이유는?

**Q3.** `Owns(&appsv1.Deployment{})` 한 줄이 가능하게 하는 동작은?

**Q4.** 일시적 API 오류를 만났을 때 Reconcile이 해야 할 일과 하지 말아야 할 일은?

**Q5.** `r.Get`이 "방금 Create한 객체"를 못 찾을 수 있는 이유는?

**Q6.** kubebuilder 마커 3종(validation/subresource/rbac)이 각각 무엇을 생성하는가요?

**Q7.** 컨트롤러가 삭제 코드 없이도 자식이 정리되는 메커니즘과, 그래도 finalizer가 필요한 경우는?

**Q8.** status에 타임스탬프를 매번 기록하면 생기는 문제는?

---

## 정답

**A1.** 이벤트(diff) 의존을 차단해 — 이벤트 유실/중복/재기동과 무관하게 **현재 상태에서 원하는 상태로 수렴**하는 멱등 로직을 강제하기 위해. 어떤 경로로 호출돼도 결과가 같습니다.

**A2.** **멱등성** — 없으면 생성, 있으면 선언으로 수렴(드리프트 복원 포함). Create는 "이미 있음" 에러 분기가 필요하고 수렴 의미가 없습니다. SSA는 필드 소유권(모듈 24)까지 명시해 다른 관리자(HPA 등)와의 충돌을 다룰 수 있습니다.

**A3.** 자식 Deployment의 **모든 변화(수정/삭제)가 부모 Website의 reconcile을 유발** — 자식 파괴 시 자동 재생성(자가 치유), 자식 상태 변화 시 status 갱신이 배선 한 줄로.

**A4.** 해야 할 일: **에러를 그대로 반환** (프레임워크가 지수 백오프로 재시도). 하지 말 것: 직접 sleep/재시도 루프(워커 점유), 에러 무시(영구 불일치).

**A5.** 읽기가 **informer 캐시**에서 오기 때문 — watch 전파 지연으로 캐시가 아직 그 객체를 못 받았을 수 있습니다(eventually consistent). "쓰고 바로 읽기"에 의존하지 않는 설계가 정답.

**A6.** validation 마커 → CRD의 OpenAPI 스키마(pattern/min/max). subresource 마커 → CRD의 status 서브리소스 선언. rbac 마커 → config/rbac/의 Role/ClusterRole YAML.

**A7.** `SetControllerReference`가 심은 ownerReference를 보고 **GC가 연쇄 삭제** (모듈 24). finalizer가 필요한 경우: **클러스터 밖 자원**(외부 DNS, 클라우드 리소스) — GC가 모르는 것들의 정리 보장.

**A8.** status 변경 → watch 이벤트 → reconcile → 또 status 변경... 의 **무한 셀프 루프** — 컨트롤러 CPU와 API 서버 부하 폭증. 항상 달라지는 값을 status에 넣지 말고, 변화 비교 후 갱신 + predicate 필터로 방어.
