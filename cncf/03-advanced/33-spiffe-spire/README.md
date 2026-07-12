# 33 — SPIFFE/SPIRE 심층: 워크로드에게 신원을 주입니다

> 07의 보안 시간선에서 "관통하는 신원" 축의 나머지 절반(19의 cert-manager가 인증서라는 물건이었다면 이것은 신원 자체). cicd 전체에서 반복한 "비밀번호를 신원 증명으로"(OIDC 07, keyless 21, IRSA)의 인프라 계층이자, 24(Istio)의 mTLS가 쓰는 SPIFFE ID의 뿌리입니다. SPIFFE는 **표준**(워크로드 신원이 무엇이고 어떻게 표현되나)이고 SPIRE는 **구현**(그 신원을 어떻게 발급·검증하나)입니다. 이 모듈의 핵심 질문은 하나입니다: 계속 바뀌는 워크로드(Pod)에게 "네가 진짜 결제 서비스임"을 어떻게 암호학적으로 증명하나 — 부트스트랩 시크릿 없이.

## 학습 목표

1. SPIFFE ID·SVID·Trust Bundle의 개념과 "워크로드 신원"이 IP·시크릿과 다른 점을 압니다
2. SPIRE의 아키텍처(server + agent)와 노드/워크로드 어테스테이션(attestation)을 이해합니다
3. **부트스트랩 신뢰 문제**("최초 신원을 어떻게" — turtles all the way down)와 SPIRE의 답을 압니다
4. SVID 발급 흐름(노드 증명 → 워크로드 증명 → SVID)을 확인합니다
5. 24의 Istio, 21의 OIDC와 SPIFFE의 관계 — 신원의 통일 — 을 압니다

## 선행: 07(신원 축 — 필수), 19(cert-manager), 24(Istio mTLS), cicd 07·21(OIDC·keyless) · 도구: kind, kubectl, helm
## 비용: 없음 (kind)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-identity-and-attestation.md](./lab-01-identity-and-attestation.md) — SPIFFE ID·SVID, 어테스테이션
3. [lab-02-bootstrap-and-federation.md](./lab-02-bootstrap-and-federation.md) — 부트스트랩 신뢰, 페더레이션·통합
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 2h + 실습 2h
