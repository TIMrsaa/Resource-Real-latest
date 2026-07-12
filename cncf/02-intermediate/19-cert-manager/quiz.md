# 자가 점검 퀴즈

**Q1.** cert-manager의 리소스 체인을 나열하세요. Issuer와 ClusterIssuer의 차이는?

**Q2.** HTTP-01과 DNS-01의 방법·필요조건·능력 차이는? 각각의 대표 실패 원인은?

**Q3.** Let's Encrypt rate limit에서 가장 자주 걸리는 항목과 그 방어는?

**Q4.** `renewalTime`은 어떻게 계산되나요? renewBefore를 너무 짧게/길게 잡으면?

**Q5.** 내부 CA 3단 체인을 구성하는 리소스는? 그 구조의 보안 리스크는?

**Q6.** 인증서 갱신 후 앱에 반영되지 않는 세 가지 경우와 각각의 원인은?

**Q7.** "갱신 완료"의 올바른 정의와 검증 방법은?

**Q8.** 사고 사례에서 루트 CA 회전이 왜 리프 갱신과 "완전히 다른 사건"인가요? 안전한 절차는?

---

## 정답

**A1.** Certificate(사용자 선언) → CertificateRequest(CSR 포함, 1회성) → [ACME인 경우 Order → Challenge(HTTP-01/DNS-01) → 검증] → Secret(type: kubernetes.io/tls — tls.crt, tls.key, ca.crt). Issuer는 네임스페이스 스코프(그 네임스페이스의 Certificate만 사용 가능), ClusterIssuer는 클러스터 스코프(전역 사용, 자격증명 Secret은 cert-manager 네임스페이스에서 읽습니다).

**A2.** HTTP-01: `http://<domain>/.well-known/acme-challenge/<token>`에 응답 — 인터넷에서 80포트 접근 가능해야 하고 와일드카드 불가. cert-manager가 임시 Pod·Service·Ingress를 만들어 응답합니다. DNS-01: `_acme-challenge.<domain>` TXT 레코드 — DNS 제공자 API 자격증명이 필요하지만 와일드카드와 내부 전용 도메인이 가능합니다. 실패 원인: HTTP-01은 80→443 리다이렉트·Ingress 라우팅·방화벽, DNS-01은 전파 지연·API 권한.

**A3.** **중복 인증서(같은 도메인 조합) 주 5개** — 설정을 시행착오로 고치다 보면 금방 소진되고 일주일간 발급이 막힙니다. 실패한 검증도 별도로 카운트됩니다(계정+호스트당 시간당 5회)므로 챌린지가 계속 실패하는 상태를 방치하면 조용히 한도를 소진합니다. 방어: 모든 실험은 스테이징 서버(`acme-staging-v02`)로, 프로덕션 Issuer는 검증 후에만 사용, 챌린지 실패를 알람으로.

**A4.** `renewalTime = notAfter - renewBefore`. renewBefore를 지정하지 않으면 duration의 1/3 지점(즉 수명의 2/3가 지난 시점)에 갱신합니다 — 90일 인증서면 만료 30일 전. 너무 짧게(예: 1시간) 잡으면 갱신이 실패했을 때 사람이 대응할 시간이 없습니다. 너무 길게 잡으면 잦은 재발급으로 ACME rate limit에 걸립니다. duration 자체는 Issuer가 허용하는 범위 안에서만 가능합니다(Let's Encrypt는 90일 고정).

**A5.** ① SelfSigned ClusterIssuer(부트스트랩) ② 루트 CA Certificate(`isCA: true`, secretName에 CA 키·인증서 저장) ③ 그 Secret을 참조하는 CA ClusterIssuer(`spec.ca.secretName`) → 이후 리프 인증서들이 이 Issuer로 발급됩니다. 리스크: **루트 CA 개인키가 클러스터 Secret에 평문(base64)으로 존재**합니다 — 클러스터 침해 = CA 침해 = 모든 내부 TLS 위조 가능. 프로덕션은 외부 PKI Issuer(Vault·AWS Private CA)나 루트 오프라인 + 중간 CA만 클러스터에.

**A6.** ① `subPath` 마운트: kubelet이 subPath 파일을 갱신하지 않습니다(K8s의 알려진 제약). ② `env`(secretKeyRef) 주입: Pod 시작 시 고정되어 재시작 전까지 옛 값. ③ 일반 볼륨은 갱신되지만 **앱이 시작 시 한 번만 파일을 읽었다면** 메모리의 인증서는 옛 것 — 파일과 앱의 상태가 다릅니다. 세 경우 모두 cicd 22에서 배운 시크릿 전파 문제의 인증서판입니다.

**A7.** 정의: Secret이 갱신된 것이 아니라 **앱이 새 인증서로 TLS 핸드셰이크를 하는 것**. 검증: 외부에서 `openssl s_client -connect <svc>:443 -servername <name> </dev/null | openssl x509 -noout -dates`로 서버가 제시하는 인증서의 notAfter를 확인합니다. 앱이 리로드를 지원하지 않으면 Reloader류로 롤링 재시작하거나, Ingress 컨트롤러·서비스 메시(SDS)가 갱신을 처리하게 합니다.

**A8.** 리프 갱신은 같은 CA가 새 인증서를 서명하는 것이라 신뢰 앵커가 그대로입니다. 루트 CA 갱신은 **새 신뢰 앵커가 생기는 것**이라, 새 루트로 서명된 인증서를 옛 루트만 신뢰하는 클라이언트가 거부합니다(사고 사례: 서비스 간 mTLS 전면 실패). 안전한 절차: ① 신·구 루트를 **동시에 신뢰하는 기간**을 만듭니다(CA 번들에 둘 다 포함, 또는 크로스 서명). ② trust-manager로 번들을 전 네임스페이스에 배포하고 앱이 다시 읽는지 검증. ③ 모든 리프가 새 루트로 재발급된 뒤 옛 루트 제거. ④ 루트 CA 만료를 리프와 **분리된 알람**으로 관리(3년짜리는 아무도 안 봅니다).
