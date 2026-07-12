# 자가 점검 퀴즈

**Q1.** Service(L4)로는 불가능하고 Ingress/Gateway(L7)로만 가능한 것 3가지를 들어라.

**Q2.** Ingress 리소스를 만들었는데 ADDRESS가 계속 빈칸입니다. 원인은?

**Q3.** Ingress가 유지보수 모드로 동결된 구조적 이유 3가지는?

**Q4.** Gateway API의 3계층 리소스와 각각의 소유 주체(팀)는?

**Q5.** "베타 헤더가 있는 요청만 v2로, 나머지는 v1:v2=90:10" — Gateway API에서 사용하는 표준 필드 2개는?

**Q6.** HTTPRoute의 status conditions에서 `ResolvedRefs: False`의 의미는?

**Q7.** Gateway 구현체 Pod 앞단의 노출은 보통 무엇으로 이루어지는가요? (모듈 05 연결)

---

## 정답

**A1.** 호스트/경로/헤더 기반 라우팅, TLS 종료(인증서 관리), 가중치 분배(카나리), (+리다이렉트/재작성/미러링 등 HTTP 수준 처리, LB 1개 공유)

**A2.** 해당 `ingressClassName`을 처리할 **Ingress Controller가 설치되어 있지 않습니다** (또는 클래스 이름 불일치). 규칙만 있고 실행체가 없는 상태.

**A3.** ① 표준 스펙의 표현력 부족 ② 부족분을 메꾼 구현체별 annotation의 비표준화(이식성 붕괴) ③ 인프라 설정과 앱 라우팅이 한 리소스에 섞임(역할/권한 미분리).

**A4.** GatewayClass(구현체 벤더), Gateway(인프라/플랫폼팀 — LB·리스너·TLS), HTTPRoute 등 Route(개발팀 — 앱 라우팅).

**A5.** `rules[].matches[].headers`(헤더 매칭)와 `rules[].backendRefs[].weight`(가중치).

**A6.** backendRefs가 가리키는 **Service(이름/포트)를 찾지 못했다**는 뜻 — 오타, 다른 네임스페이스, 포트 불일치 등.

**A7.** **LoadBalancer 타입 Service** (클라우드 LB → 구현체 Pod). 즉 Gateway는 Service 위에 L7 한 층을 얹은 구조입니다.
