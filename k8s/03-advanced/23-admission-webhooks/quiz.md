# 자가 점검 퀴즈

**Q1.** ValidatingAdmissionPolicy(CEL)가 웹훅보다 우선 검토되어야 하는 이유 3가지는?

**Q2.** 그럼에도 웹훅이 필요한 경우 2가지는?

**Q3.** API 서버가 웹훅을 호출할 때 보내는 객체와, 웹훅이 반환해야 하는 응답의 핵심 필드는?

**Q4.** "labels에 team 키가 있고 값이 team-으로 시작"을 안전하게 검사하는 CEL 식을 쓰라.

**Q5.** failurePolicy: Fail 웹훅의 운영 의무사항 4가지는?

**Q6.** 정책 도입 시 validationActions의 3단계 경로와 각 단계의 목적은?

**Q7.** "웹훅이 자기 자신을 부활시키지 못하는 데드락"의 구조와 예방책은?

**Q8.** paramKind/paramRef가 가능하게 하는 설계 패턴은?

---

## 정답

**A1.** ① API 서버 **인프로세스** 평가라 네트워크 왕복/외부 장애 지점이 없다 ② 웹훅 서버 운영(HA, TLS, 인증서 갱신) 부담이 없다 ③ 지연이 거의 0이라 모든 요청에 부담 없이 적용 가능.

**A2.** ① **외부 데이터 조회**가 필요한 검증(이미지 서명 확인, 외부 CMDB 대조) ② **변형(mutate)** 이 필요한 경우(사이드카/기본값 주입 — MutatingAdmissionPolicy가 성숙하기 전까지).

**A3.** 보냄: **AdmissionReview** (request.uid, object, oldObject, userInfo...). 응답: response에 **uid(요청과 동일), allowed(bool)**, 거부 시 status.message, mutating이면 patchType+patch(base64 JSONPatch).

**A4.** `has(object.metadata.labels) && 'team' in object.metadata.labels && object.metadata.labels['team'].startsWith('team-')` (존재 확인 없이 접근하면 평가 에러 → 의도치 않은 거부).

**A5.** ① 웹훅 서버 HA(replicas 2+, PDB, AZ 분산) ② namespaceSelector로 kube-system과 웹훅 자신 ns 제외 ③ timeoutSeconds 단축(≤5s) ④ rules/셀렉터로 대상 최소화.

**A6.** **Audit**(거부 없이 감사 로그 — 위반 현황 파악) → **Warn**(kubectl에 경고 — 개발자 교육/유예기간) → **Deny**(강제). 빅뱅 강제로 인한 배포 마비를 막는 경로.

**A7.** 웹훅 Pod 사망 → 대체 Pod 생성 요청이 그 웹훅의 검사 대상 → 웹훅이 없어 Fail 정책으로 거부 → 영원히 부활 불가. 예방: **웹훅 자신의 ns(와 kube-system)를 namespaceSelector로 제외.**

**A8.** **정책 로직과 정책 데이터의 분리** — 같은 CEL 정책을 ns/팀마다 다른 파라미터(ConfigMap 등)로 바인딩해 "팀별 한도" 같은 일반화된 정책 제품을 만듭니다 (Kyverno/Gatekeeper 패턴의 원형).
