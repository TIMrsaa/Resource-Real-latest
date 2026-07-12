# 이론 — SPIFFE 개념, SPIRE 아키텍처, 어테스테이션, 부트스트랩, 통합

> **🌱 17세 눈높이 비유: 신입 사원증 발급**
> - **문제**: 매일 새 인턴(Pod)이 오는데, 각자에게 "진짜 우리 회사 사람"임을 증명하는 사원증(신원)을 어떻게 주나요? 비밀번호를 미리 알려주면 유출되고, 얼굴(IP)은 매번 바뀝니다
> - **SPIFFE ID** = 사원증에 적힌 표준 형식의 이름 (spiffe://회사/부서/직급)
> - **SVID** = 실제 사원증 (위조 방지 홀로그램 = 인증서)
> - **어테스테이션** = 사원증 발급 전 신원 확인 — "이 사람이 정말 이 건물(노드) 3층(K8s SA)에서 왔나"를 플랫폼 기록으로 검증. 본인 주장이 아니라 증명
> - **부트스트랩 문제** = "그럼 최초의 신원 확인은 누가?" — 건물 자체가 진짜 우리 건물인지부터(노드 어테스테이션) 시작하는 신뢰 사슬
> - **Trust Bundle** = 사원증 진위를 확인하는 회사 공식 도장 (루트 CA)

---

## 1. SPIFFE 개념 — 표준

```
SPIFFE ID (표준 형식의 워크로드 이름):
  spiffe://<trust-domain>/<path>
  예: spiffe://example.org/ns/prod/sa/payment
  → trust domain(신뢰 영역) + 계층적 경로
  → 24(Istio)의 mTLS 신원이 정확히 이 형식

SVID (SPIFFE Verifiable Identity Document — 실제 신원 문서):
  X.509-SVID: X.509 인증서 (SAN에 SPIFFE ID) — mTLS용 (19의 인증서와 연결)
  JWT-SVID: JWT (sub에 SPIFFE ID) — 토큰 기반 인증용

Trust Bundle:
  SVID를 검증하는 신뢰 앵커(루트 CA/공개키)
  → "이 SVID가 진짜 이 trust domain의 것인가" 검증 (19의 CA 번들)

Workload API:
  워크로드가 자기 SVID를 받는 표준 API (유닉스 소켓)
  → 앱이 소켓에서 SVID를 받습니다 (시크릿 파일·환경변수 아님)
```

## 2. SPIRE 아키텍처 — 구현

```
SPIRE Server (중앙):
  - 신뢰 영역의 루트 (SVID 발급, Trust Bundle 관리)
  - 등록 항목(registration entry): "어떤 속성의 워크로드에 어떤 SPIFFE ID를"
  - 노드 어테스테이션 검증

SPIRE Agent (노드당, DaemonSet):
  - 노드 어테스테이션 (이 노드가 진짜인지 Server에 증명)
  - 워크로드 어테스테이션 (이 프로세스가 누구인지 검증)
  - Workload API 제공 (워크로드에 SVID 전달)

흐름:
  Agent가 노드 증명 → Server가 노드 SVID 발급
  워크로드가 Workload API 호출 → Agent가 워크로드 증명(프로세스 속성)
  → Server가 등록 항목과 대조 → SVID 발급 → 워크로드에 전달
```

## 3. 어테스테이션 — 신원의 증명

```
노드 어테스테이션 (이 노드가 진짜인가):
  k8s_psat: K8s Projected Service Account Token (노드의 SA 토큰 검증)
  aws_iid: AWS Instance Identity Document (EC2 인스턴스 증명)
  gcp_iit, azure_msi: 클라우드별
  join_token: 수동 토큰 (부트스트랩용)
  → "이 노드가 정말 이 클라우드의 이 인스턴스/이 K8s 노드인가"

워크로드 어테스테이션 (이 프로세스가 누구인가):
  k8s: Pod의 속성 (namespace, service account, labels...)
  unix: 프로세스의 uid/gid/path
  docker: 컨테이너 속성
  → Agent가 호출한 프로세스의 커널 수준 속성을 검증
     (프로세스가 "나는 결제 서비스야"라고 주장 ✗, 커널이 그 프로세스의 실체를 ✓)

★ 핵심: 워크로드는 자기 신원을 '주장'하지 않습니다
  플랫폼(노드·커널·클라우드)의 검증 가능한 속성으로 '증명'됩니다
  → 위조 불가 (시크릿 유출로 신원 도용이 안 됨)
```

## 4. 부트스트랩 신뢰 — turtles의 바닥

```
문제 (guide): 신원을 주려면 확인해야, 확인하려면 뭔가를 신뢰해야, 그 신뢰는?

SPIRE의 답 — 신뢰의 사슬을 플랫폼에 뿌리내립니다:
  1. SPIRE Server가 신뢰의 루트 (여기가 시작점)
  2. 노드 어테스테이션: 노드가 클라우드/K8s의 검증 가능한 증거로 증명
     (AWS IID는 AWS가 서명, K8s SAT는 API 서버가 검증)
     → 신뢰의 뿌리가 '플랫폼'(클라우드·K8s)에 있습니다
  3. 워크로드 어테스테이션: 증명된 노드 위의 Agent가 워크로드를 커널 속성으로 증명
  → 최초 시크릿 없이, 플랫폼의 이미 존재하는 신뢰(클라우드가 인스턴스를 아는 것)에서 시작

07의 OIDC와 같은 통찰:
  "부트스트랩 시크릿을 없앤다" = 플랫폼이 이미 아는 것(신원)을 활용
  GitHub이 워크플로를 아는 것(OIDC), AWS가 인스턴스를 아는 것(IID),
  K8s가 Pod의 SA를 아는 것(PSAT) → 이것이 신뢰의 바닥
```

## 5. SVID 수명주기

```
발급: 어테스테이션 통과 → 짧은 수명 SVID (기본 1시간)
갱신: 만료 전 자동 갱신 (Workload API가 새 SVID를 push)
회전: 짧은 수명이라 유출돼도 곧 만료 (07·22의 단명 원리)
Trust Bundle 회전: 루트 CA 회전 (19·24의 CA 만료 교훈 — 신·구 병존)

★ 앱은 Workload API 소켓에서 SVID를 받습니다:
  시크릿 파일도(22의 전파 문제 회피), 환경변수도 아님
  → SDK가 소켓에서 최신 SVID를 받아 자동 갱신
```

## 6. 통합 — 신원의 통일

```
SPIFFE를 쓰는 것들:
  Istio(24): 사이드카 mTLS의 신원이 SPIFFE ID (istiod가 SPIRE 역할 또는 SPIRE 통합)
  Envoy(23): SDS로 SPIFFE SVID 수신
  cert-manager(19): csi-driver-spiffe로 SVID를 인증서로
  Kubernetes: 향후 워크로드 신원의 표준 방향

07의 신원 축 통일:
  cert-manager(19): 인증서라는 물건
  SPIFFE/SPIRE(33): 워크로드 신원 자체 (그 인증서/토큰의 주인이 누구인가)
  OIDC(07)·keyless(21): 외부(클라우드·CI) 신원
  → 전부 "검증 가능한 신원"으로 수렴 (공유 시크릿의 종말)

멀티 클러스터·멀티 클라우드:
  페더레이션: 다른 trust domain 간 신뢰 (Trust Bundle 교환)
  → 여러 클러스터·조직의 워크로드가 서로 신원 검증
```

## 7. 소스/도구에서 확인하기

- SPIFFE: https://spiffe.io/docs — concepts, SVID, Workload API
- SPIRE: https://spiffe.io/docs/latest/spire-about/ — server, agent, attestation
- 어테스테이션 플러그인: https://github.com/spiffe/spire/tree/main/doc
- 07(신원)·19(cert-manager)·24(Istio)·21(keyless) 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| SPIFFE vs SPIRE? | 표준(신원이 무엇인가) vs 구현(어떻게 발급·검증) |
| SPIFFE ID? | spiffe://trust-domain/path — 24 Istio mTLS의 그 신원 |
| SVID? | 검증 가능한 신원 문서(X.509 또는 JWT) — 각자의 인증서 |
| 어테스테이션? | 워크로드가 '주장' 아니라 플랫폼 속성으로 '증명' (위조 불가) |
| 부트스트랩 답? | 신뢰를 플랫폼(클라우드·K8s)의 기존 신원에 뿌리 (07의 OIDC 통찰) |
| IP·시크릿과 차이? | 재생성에 불변(22), 유출돼도 그 워크로드 하나(공유 시크릿 아님) |
| 앱이 SVID 받는 법? | Workload API 소켓 (시크릿 파일·env 아님 — 22의 전파 회피) |
| 신원의 통일? | Istio·Envoy·cert-manager·OIDC가 SPIFFE로 수렴 |
