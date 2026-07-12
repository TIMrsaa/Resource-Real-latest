# 자가 점검 퀴즈

**Q1.** clientset과 dynamic 클라이언트의 트레이드오프는?

**Q2.** informer 파이프라인의 부품 5개(Reflector→...→워커)와 각 책임을 쓰라.

**Q3.** workqueue에 객체가 아닌 "키"를 넣는 이유 2가지는?

**Q4.** AddRateLimited와 Forget의 역할과, 모듈 30의 어떤 동작이 이것의 포장인가요?

**Q5.** resync는 API 서버를 다시 조회하는가요? 그 용도는?

**Q6.** Lister에서 받은 객체를 바로 수정하면 안 되는 이유는?

**Q7.** "이미 수렴이면 쓰기 생략" 체크가 없을 때 생기는 일은?

**Q8.** informer의 watch 범위를 좁히는 3가지 수단과 그 이득은?

---

## 정답

**A1.** clientset: 정적 타입 — 컴파일 타임 안전/자동완성, 단 내장 리소스만. dynamic: Unstructured(map) — **CRD 포함 임의 리소스** 가능, 대신 경로 오타가 런타임에야 드러남.

**A2.** **Reflector**: List+Watch 실행, 단절 시 rv부터 재개(410이면 relist). **DeltaFIFO**: 변경 순서 보존 버퍼. **Indexer**: 스레드 안전 로컬 캐시+색인 (읽기의 출처). **이벤트 핸들러**: 키를 큐에 넣기만. **워커**: 큐에서 키를 꺼내 캐시를 읽고 처리.

**A3.** ① **중복 압축** — 처리 전 같은 키 N번 = 1번 처리 ② **낡은 사본 방지** — 객체를 넣으면 처리 시점에 이미 옛날 것; 키만 넣고 처리 시 캐시에서 최신을 읽습니다.

**A4.** AddRateLimited: 실패한 키를 **지수 백오프**로 재큐잉. Forget: 성공 시 백오프 카운터 리셋. — 모듈 30의 "Reconcile에서 err만 반환하면 자동 재시도"의 구현 실체.

**A5.** **아니오** — 로컬 캐시의 모든 객체를 Update 핸들러로 재전달할 뿐(API 호출 없음). 용도: 놓친 이벤트/핸들러 버그로 생긴 불일치의 주기적 자기 치유.

**A6.** 그 포인터는 **공유 캐시의 원본**이라 수정이 캐시를 오염시켜, 같은 informer를 쓰는 모든 코드가 가짜 상태를 보게 됩니다. 수정 전 DeepCopy().

**A7.** 내 쓰기가 Update 이벤트를 낳고 → 다시 reconcile → 또 쓰기... 의 **무한 셀프 루프** (모듈 30 pitfall 3). 수렴 비교(또는 predicate)가 차단기입니다.

**A8.** factory 옵션의 **LabelSelector / FieldSelector / Namespace 한정** (+메타데이터만 필요하면 PartialObjectMetadata). 이득: 캐시 메모리 절감 + List/Watch의 API·etcd 부하 절감 + 보안 노출 면적 축소.
