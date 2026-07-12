# 19 — cert-manager 심층: 인증서를 잊는 법

> 07의 보안 시간선에서 "관통하는 신원" 축의 절반. cert-manager가 없애는 고통은 구체적입니다 — **인증서 만료로 인한 새벽 장애**. 갱신을 캘린더와 사람의 기억에 맡기던 시대를 끝낸 프로젝트이고, 그 방법은 K8s의 문법 그대로입니다: Certificate라는 선언을 두면 컨트롤러가 발급·갱신·회전을 수렴시킵니다(08의 오퍼레이터 패턴). 이 모듈은 발급의 실제(ACME 챌린지의 두 방식), 갱신 타이밍의 계산, 그리고 프로덕션의 급소(rate limit·DNS 전파·Secret 회전 후 앱 반영)를 팝니다.

## 학습 목표

1. 리소스 모델(Issuer/ClusterIssuer → Certificate → CertificateRequest → Order/Challenge → Secret)을 압니다
2. ACME 챌린지 HTTP-01과 DNS-01의 차이와 각각의 필요 조건을 압니다
3. 갱신 타이밍(renewBefore·duration)과 Let's Encrypt rate limit을 계산합니다
4. 내부 CA(선택적 self-signed → CA Issuer 체인)로 사설 인증서 체계를 세웁니다
5. 갱신된 Secret이 앱에 반영되지 않는 문제(cicd 22의 전파 문제)를 해결합니다

## 선행: 07(보안 지도), k8s(Ingress·Secret), eks 20(mTLS) · 도구: kind, kubectl, helm, openssl
## 비용: 없음 (kind + self-signed/내부 CA; ACME는 개념·스테이징만)

## 진행 순서

1. [guide.md](./guide.md) → [theory.md](./theory.md)
2. [lab-01-issuers-and-lifecycle.md](./lab-01-issuers-and-lifecycle.md) — 리소스 체인, 발급, 갱신 타이밍
3. [lab-02-internal-ca-and-rotation.md](./lab-02-internal-ca-and-rotation.md) — 내부 CA, 회전과 앱 반영
4. [quiz.md](./quiz.md) → [pitfalls.md](./pitfalls.md) → `bash cleanup.sh`

소요: 이론 1.5h + 실습 2.5h
