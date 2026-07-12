# 자가 점검 퀴즈

**Q1.** 노드 역할 공유와 Secret 키 보관이 각각 금지인 이유는?

**Q2.** IRSA의 6단계 경로(배선 3 + 런타임 3)를 그려라.

**Q3.** IRSA 신뢰 정책의 Condition 두 줄과 Pod 토큰의 어느 클레임이 대응되는가요?

**Q4.** Pod Identity가 IRSA 대비 단순화한 3지점은?

**Q5.** 앱 코드 무수정으로 둘 다 동작하는 원리와, 그 체인의 위험한 마지막 칸은?

**Q6.** "권한을 줬는데 안 돼요" 디버깅 4단계 루틴은?

**Q7.** Pod Identity 세션 태그가 여는 패턴은?

**Q8.** IRSA→Pod Identity 마이그레이션의 안전 순서는?

---

## 정답

**A1.** 노드 역할 공유: 그 노드의 모든 Pod이 동일 권한 — Pod 단위 최소 권한 붕괴, 침해 시 익명화. Secret 키: 장수 자격증명의 회전/유출 문제(k8s 07) — 둘 다 "짧은 수명 + 신원 단위" 원칙 위반.

**A2.** 배선: ① 클러스터 OIDC issuer를 IAM 공급자로 등록 ② 역할+신뢰 정책(sub=ns:SA 조건) ③ SA에 role-arn 어노테이션. 런타임: ④ webhook이 projected 토큰+환경변수 주입 ⑤ SDK가 AssumeRoleWithWebIdentity ⑥ STS가 서명/sub/aud 검증 → 임시 자격증명.

**A3.** `"<issuer>:sub": "system:serviceaccount:<ns>:<sa>"` ↔ 토큰의 `sub` 클레임 / `"<issuer>:aud": "sts.amazonaws.com"` ↔ 토큰의 `aud`. (+iss는 공급자 등록 자체와 대응)

**A4.** ① 클러스터별 OIDC 공급자 등록 불필요 ② 신뢰 정책이 고정 문구(pods.eks.amazonaws.com — 역할 재사용) ③ 매핑이 SA 어노테이션 대신 EKS API의 association(전수 조회/IaC/감사 용이). (+자동 세션 태그)

**A5.** SDK 자격증명 체인 — webhook이 주입한 환경변수(IRSA: web identity / PI: 컨테이너 URI)가 체인에 걸려 자동 사용. 마지막 칸 = **IMDS(노드 역할) 폴백**: 배선 실패가 조용히 노드 권한으로 동작하는 구멍.

**A6.** ① Pod에서 `env | grep AWS_`(주입 여부 — 없으면 webhook/association/어노테이션) ② `aws sts get-caller-identity`(누구로 동작 중 — 노드 역할이면 폴백) ③ 거부면 역할의 권한 정책 vs 호출 API, (IRSA) 신뢰 정책 sub 글자 대조 / (PI) association의 ns·SA ④ 설정 변경 후 Pod 재시작 했는지.

**A7.** 세션에 클러스터/ns/SA 태그가 자동으로 붙어, 역할 정책의 Condition(`aws:PrincipalTag/...`)으로 **하나의 공유 역할을 ns별 리소스 접근으로 정밀 분할** — 역할 수 폭증 없이 최소 권한.

**A8.** ① 역할 신뢰 정책에 PI 문구 추가(IRSA 문구와 병존) ② association 생성 ③ Pod 재기동 후 검증(env가 URI 방식 + caller-identity) ④ 안정 후 SA 어노테이션 제거, 전체 완료 시 OIDC 조건/공급자 정리 — 병존→검증→제거, 빅뱅 금지.
