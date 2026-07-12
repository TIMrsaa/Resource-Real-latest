# 이론 — IRSA 해부, Pod Identity, 자격증명 체인

> **🌱 17세 눈높이 비유: 학생증으로 시립도서관 이용하기**
> 학교(K8s)가 발급한 학생증(SA 토큰)으로 시립도서관(AWS)을 이용하려면?
> - **IRSA** = 시청과 학교가 **공증 협약**(OIDC 공급자 등록)을 맺고, 도서관 창구(STS)가 학생증의 학교 도장을 공증 체계로 검증 후 **일일 이용권**(임시 자격증명)을 발급. 협약 서류(신뢰 정책)에 "어느 반(ns) 어느 학생(SA)"까지 명시
> - **Pod Identity** = 교육청(EKS)이 도서관에 **상주 직원**(에이전트)을 파견 — 학생은 학생증만 보여주면 직원이 알아서 이용권을 떼줍니다. 학교마다 공증 협약을 맺을 필요가 없어졌습니다
> 공통 결과: 학생은 **장기 회원증(영구 키)을 가진 적이 없습니다** — 잃어버려도 하루짜리

---

## 1. IRSA — 경로 전체 해부

### 배선 (클러스터당 1회 + 역할마다)

```
① 클러스터의 OIDC issuer (eks 02 lab-01에서 본 URL)를
   IAM의 OIDC identity provider로 등록    ← "학교 공증 등록"
② IAM 역할 생성 + 신뢰 정책:
   Principal: 그 OIDC 공급자
   Condition: sub == "system:serviceaccount:<ns>:<sa>"   ← 어느 SA에게만!
③ SA에 어노테이션: eks.amazonaws.com/role-arn: <역할 ARN>
```

### 런타임 (Pod 기동마다 — 마법의 정체)

```
④ EKS의 mutating webhook(또 너구나 — k8s 23!)이 그 SA를 쓰는 Pod에 주입:
   - projected SA 토큰 볼륨 (audience: sts.amazonaws.com, k8s 11의 그 토큰)
   - 환경변수: AWS_ROLE_ARN, AWS_WEB_IDENTITY_TOKEN_FILE
⑤ 앱의 AWS SDK가 자격증명 체인에서 그 변수를 발견
   → STS AssumeRoleWithWebIdentity(토큰 제출)
⑥ STS가 토큰 서명을 OIDC 공급자(=클러스터의 공개키)로 검증, sub 조건 대조
   → 임시 자격증명 (기본 1시간, SDK가 자동 갱신)
```

핵심 통찰: **K8s가 신원의 발급자, AWS는 검증자** — 비밀 공유가 아니라 공개키 연합. 토큰은 짧고(만료), 역할 매핑은 ns+SA 단위로 정밀합니다.

## 2. Pod Identity — 무엇이 단순해졌나

```
배선: ① eks-pod-identity-agent 애드온 (노드마다, 한 번)
     ② IAM 역할 신뢰 정책: Principal = pods.eks.amazonaws.com   ← 클러스터 무관 고정!
     ③ association 생성: (클러스터, ns, SA) ↔ 역할   ← EKS API 객체
런타임: webhook이 컨테이너 자격증명 URI(169.254.170.23)와 토큰 변수 주입
       → SDK가 그 URI 호출 → 노드의 에이전트가 eks-auth(AssumeRoleForPodIdentity)
       → 임시 자격증명
```

| | IRSA | Pod Identity |
|---|------|--------------|
| 클러스터별 OIDC 공급자 등록 | 필요 | **불필요** |
| 역할 신뢰 정책 | 클러스터/SA마다 다름 | **모든 클러스터 동일** (재사용!) |
| 매핑 위치 | SA 어노테이션 (K8s 안) | **association (EKS API)** — IaC/감사 친화 |
| 멀티 클러스터에 같은 역할 | 신뢰 정책 수정 지옥 | association만 추가 |
| 적용 범위 | EKS 밖에서도 (일반 OIDC) | EKS 전용 |
| 세션 태그 | 제한적 | 클러스터/ns/SA 자동 태그 (정책 조건 활용) |

→ **신규는 Pod Identity 기본**, IRSA가 남는 곳: 비EKS(자체 운영) 클러스터, 일부 미지원 케이스, 기존 환경.

## 3. SDK 자격증명 체인 — "코드 수정 없음"의 원리

AWS SDK는 자격증명을 정해진 순서로 찾습니다:

```
명시 키 → 환경변수 → ★web identity 토큰(IRSA) → ★컨테이너 자격증명 URI(Pod Identity)
→ ... → IMDS(노드 역할 — 최후의 폴백!)
```

- webhook이 꽂아준 변수/URI가 체인에 걸리므로 **앱 코드는 한 줄도 안 바뀝니다**
- 함정: 배선이 빠지면 조용히 **IMDS(노드 역할)로 폴백** — "되긴 되는데 누구 권한으로?"의 정체. 노드 역할을 최소화하고 IMDS hop limit을 줄여(또는 차단) 폴백을 시끄럽게 만들어야 합니다 (25)

## 4. 디버깅 루틴 (양쪽 공통)

```
① kubectl exec <pod> -- env | grep AWS_     배선 확인 (변수가 없으면 webhook/association 문제)
② aws sts get-caller-identity (Pod 안에서)  지금 누구인가 — assumed-role/<역할>이어야
③ 권한 거부면: 역할 정책 vs 호출 API 대조 / 신뢰 정책의 sub 오타(IRSA) / association의 ns·SA(PI)
④ Pod 재시작 했나요? (배선은 기동 시 주입 — 어노테이션/association 변경 후 재기동 필수)
```

## 5. 소스/도구에서 확인하기

- IRSA 내부 문서: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html
- Pod Identity: https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html
- webhook 구현(IRSA): github.com/aws/amazon-eks-pod-identity-webhook — 주입 로직 원문
- SDK 체인 문서: 각 SDK의 credential provider chain

## 요약 카드

| 질문 | 답 |
|------|----|
| 노드 역할 공유의 죄? | 그 노드 전체 Pod이 같은 권한 — 최소 권한 붕괴 |
| IRSA 한 줄 요약? | SA 토큰(OIDC)을 STS가 검증해 임시 자격증명 교환 |
| Pod Identity의 단순화? | OIDC 등록/신뢰 정책 커스텀 불필요 — association으로 매핑 |
| 코드 무수정의 비밀? | SDK 자격증명 체인 + webhook 주입 |
| 조용한 폴백의 위험? | 배선 실패 시 IMDS(노드 역할)로 — 노드 역할 최소화 |
| 변경 후 안 먹어요? | Pod 재시작(주입은 기동 시) |
