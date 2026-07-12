# 자가 점검 퀴즈

**Q1.** CRD를 등록하는 순간 API 서버가 자동으로 제공하는 것 4가지는?

**Q2.** status 서브리소스를 분리하는 두 가지 이유는?

**Q3.** scale 서브리소스를 선언하면 호환되는 기존 도구 2가지는?

**Q4.** GC가 부모-자식을 결합하는 키와, 그로 인한 "부모 재생성" 함정은?

**Q5.** foreground / background / orphan 삭제의 차이는?

**Q6.** 리소스가 Terminating에 갇혔을 때의 진단→해소 순서는? (수동 finalizer 제거의 위치 포함)

**Q7.** SSA에서 conflict가 났을 때 가능한 해소 3가지와, "HPA + replicas" 문제의 SSA식 정답은?

**Q8.** "CRD + 컨트롤러" 조합에서 각각의 역할을 명사/동사로 설명하세요.

---

## 정답

**A1.** ① REST API 엔드포인트(CRUD+watch) ② 스키마 기반 검증 ③ kubectl 통합(get/explain/출력컬럼) ④ RBAC 적용 가능한 리소스 단위. (+etcd 저장, discovery 등록)

**A2.** ① **권한 분리** — 사용자는 spec만, 컨트롤러는 status만 쓰도록 RBAC 구성 가능 ② **충돌 분리** — spec 업데이트와 status 업데이트가 서로의 resourceVersion 경쟁을 일으키지 않음.

**A3.** `kubectl scale`과 **HPA** (autoscaling이 scale 서브리소스를 통해 동작하므로 커스텀 리소스도 오토스케일링 대상이 됩니다).

**A4.** **uid**. 부모를 삭제 후 같은 이름으로 재생성하면 uid가 달라서, 옛 자식들의 ownerReference는 "존재하지 않는 부모"를 가리키게 되어 **GC가 자식들을 삭제**합니다.

**A5.** background(기본): 부모 먼저 지우고 GC가 자식을 비동기 정리. foreground: 자식을 다 지운 뒤 부모 삭제(부모가 Terminating으로 대기). orphan: 부모만 지우고 자식의 ownerReference를 제거해 살려둠.

**A6.** ① 무엇이 남았나: 객체의 `metadata.finalizers`와 (ns라면) 내부 잔존 리소스 확인 ② 그 finalizer의 담당 컨트롤러 상태/로그 확인 — 살아 있으면 에러 수정 ③ 컨트롤러를 복구할 수 없을 때 **최후수단**으로 수동 제거 — 단 외부 자원 고아화를 감수하고 수동 정리 병행.

**A7.** ① `--force-conflicts`로 소유권 강탈 ② 기존 소유자가 manifest에서 해당 필드를 빼 소유 포기 ③ 설계 변경으로 소유자를 일원화. HPA 문제의 정답: **사람/GitOps의 manifest에서 replicas를 제거**해 HPA(컨트롤러)가 유일한 소유자가 되게 합니다.

**A8.** CRD = **명사 등록** ("Website라는 개념이 존재한다" — 저장/검증/API). 컨트롤러 = **동사 부여** ("Website가 선언되면 Deployment를 만들고 상태를 보고한다" — 조정 루프). 둘이 합쳐 Operator.
