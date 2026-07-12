# 이론 — 리소스 체인, ACME 챌린지, 갱신 타이밍, 내부 CA, 전파

> **🌱 17세 눈높이 비유: 학생증 발급과 갱신**
> - **Certificate** = "나 학생증 필요해요"라는 신청서 (선언)
> - **Issuer / ClusterIssuer** = 발급 창구 — 학과 사무실(네임스페이스 전용) vs 학교 본부(클러스터 전역)
> - **CertificateRequest** = 창구가 만든 실제 발급 요청서
> - **Order / Challenge** = 외부 기관(ACME)에 "이 사람이 진짜 이 학교 학생인지" 증명하는 절차
>   - **HTTP-01** = "네 교실 문에 쪽지를 붙여봐" (그 도메인의 웹 경로에 파일)
>   - **DNS-01** = "학교 게시판에 공고를 올려봐" (DNS TXT 레코드) — 와일드카드 가능
> - **Secret** = 발급된 학생증 (tls.crt + tls.key)
> - **갱신** = 만료 전에 자동으로 새 학생증 — 그런데 **지갑에 든 옛날 것을 안 바꾸면** 소용없습니다(전파 문제)

---

## 1. 리소스 체인 — 무엇이 무엇을 만드나

```
Certificate (사용자가 선언)
   │ cert-manager 컨트롤러가 감시
   ▼
CertificateRequest  (CSR 포함, 1회성)
   │ Issuer 종류에 따라
   ├─ [ACME]  Order → Challenge(HTTP-01/DNS-01) → 검증 → 발급
   ├─ [CA]    내부 CA 키로 즉시 서명
   ├─ [SelfSigned] 자기가 서명
   └─ [Vault/Venafi/AWS PCA] 외부 PKI에 요청
   ▼
Secret (type: kubernetes.io/tls — tls.crt, tls.key, [ca.crt])
```

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: app-tls, namespace: apps }
spec:
  secretName: app-tls                    # 결과가 여기에
  issuerRef: { name: letsencrypt, kind: ClusterIssuer }
  dnsNames: ["app.example.com", "*.app.example.com"]
  duration: 2160h                        # 90일 (기본은 Issuer에 따름)
  renewBefore: 720h                      # 만료 30일 전에 갱신
  privateKey:
    algorithm: ECDSA
    size: 256
    rotationPolicy: Always               # ★ 갱신 시 키도 새로 (권장)
  usages: [server auth, digital signature]
```

**Issuer vs ClusterIssuer**: 네임스페이스 스코프 vs 클러스터 스코프. ClusterIssuer의 자격증명 Secret은 cert-manager 네임스페이스에서 읽습니다.

## 2. ACME 챌린지 — 도메인 소유 증명

| | HTTP-01 | DNS-01 |
|---|---|---|
| 방법 | `http://<domain>/.well-known/acme-challenge/<token>`에 응답 | `_acme-challenge.<domain>` TXT 레코드 |
| 필요 조건 | 인터넷에서 80포트 접근 가능 | DNS 제공자 API 자격증명 |
| **와일드카드** | ❌ 불가 | ✅ 가능 |
| 내부 전용 도메인 | ❌ | ✅ (외부 접근 불필요) |
| 실패 원인 | Ingress 라우팅, 방화벽, 리다이렉트(80→443) | DNS 전파 지연, API 권한 |

```
HTTP-01의 내부 동작:
  cert-manager가 임시 Pod + Service + Ingress를 만듭니다
  → ACME 서버가 http://domain/.well-known/... 를 긁습니다
  → 성공하면 임시 리소스 삭제
  ★ 기존 Ingress가 80을 443으로 리다이렉트하면 실패합니다(흔한 함정)

DNS-01의 내부 동작:
  cert-manager가 DNS API로 TXT 레코드를 생성
  → 전파를 기다립니다(propagation check)
  → ACME 서버가 조회 → 성공하면 TXT 삭제
  ★ 전파 지연·캐시로 수 분 걸릴 수 있습니다. Route53 등 제공자별 solver 설정 필요
```

### Let's Encrypt rate limit (프로덕션 급소)

```
같은 등록 도메인(registered domain)당: 주 50개 인증서
중복 인증서(같은 도메인 조합): 주 5개      ★ 여기서 대부분 걸립니다
실패한 검증: 계정+호스트당 시간당 5회

→ 테스트는 반드시 스테이징 서버(acme-staging-v02)로!
   https://acme-staging-v02.api.letsencrypt.org/directory
→ 실수로 프로덕션에서 반복 발급하면 일주일 잠깁니다
```

## 3. 갱신 타이밍의 계산

```
발급: notBefore ~ notAfter (duration)
갱신 시점 = notAfter - renewBefore
  기본값: renewBefore 미지정 시 duration의 1/3 지점에서 갱신
          (90일 인증서 → 만료 30일 전에 갱신)

★ renewBefore를 너무 짧게 잡으면(예: 1h) 갱신 실패 시 복구 시간이 없습니다
★ 너무 길게 잡으면 rate limit에 걸립니다(잦은 재발급)
★ duration은 Issuer가 허용하는 범위 안에서만 (Let's Encrypt는 90일 고정)
```

```bash
# 상태 확인
kubectl get certificate -A
kubectl describe certificate app-tls    # Conditions: Ready, Issuing
kubectl get certificaterequest,order,challenge -A   # 발급 진행 중일 때만 존재
```

## 4. 내부 CA — 사설 PKI 체계

```
① SelfSigned Issuer → ② 루트 CA Certificate(isCA: true) → ③ CA Issuer → ④ 리프 인증서들

apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: { name: selfsigned }
spec: { selfSigned: {} }
---
kind: Certificate                    # 루트 CA
spec:
  isCA: true
  commonName: internal-root
  secretName: root-ca-secret
  issuerRef: { name: selfsigned, kind: ClusterIssuer }
  privateKey: { algorithm: ECDSA, size: 256 }
  duration: 87600h                   # 10년
---
kind: ClusterIssuer                  # 그 CA로 서명하는 Issuer
metadata: { name: internal-ca }
spec: { ca: { secretName: root-ca-secret } }
```

```
용도: 내부 서비스 간 mTLS(eks 20), 웹훅 서버 인증서(admission — 07), 사설 도메인
주의: 루트 CA 키의 보관 — 클러스터 Secret에 두면 클러스터 침해 = CA 침해
      (프로덕션은 Vault·AWS PCA 같은 외부 PKI Issuer 검토)
trust-manager: 루트 CA 번들을 여러 네임스페이스에 배포하는 자매 프로젝트
```

## 5. 전파 — 갱신의 마지막 홉 (cicd 22의 문제)

```
Secret이 갱신됐습니다. 앱이 새 인증서를 쓰는가요?

volume 마운트(일반):  kubelet이 주기적으로(수십 초~분) 파일을 갱신 ✅
volume + subPath:     ❌ 갱신 안 됨 (K8s의 알려진 제약)
env(from Secret):     ❌ Pod 재시작 전까지 옛 값
앱이 시작 시 1회 읽음: ❌ 파일은 바뀌었지만 메모리의 인증서는 옛 것

해법:
  - 앱이 파일 변경을 감지해 리로드 (nginx: SIGHUP, envoy: SDS)
  - Reloader 등으로 Secret 변경 시 롤링 재시작
  - Ingress 컨트롤러는 대개 감지·리로드(구현 확인 필요)
  - 서비스 메시(eks 20)는 SDS로 무중단 회전
★ "갱신 완료"의 정의: Secret 변경이 아니라 앱이 새 인증서로 핸드셰이크하는 것
```

## 6. 운영 관측

```
메트릭:
  certmanager_certificate_expiration_timestamp_seconds  ← 만료 시각
  certmanager_certificate_ready_status                  ← Ready 여부
알람(필수):
  (expiration - now) < 7d 이고 Ready=False  → 갱신 실패, 즉시 대응
  ACME 챌린지 반복 실패 (rate limit 소진 위험)
디버깅 순서:
  Certificate → CertificateRequest → Order → Challenge 의 조건을 순서대로
  kubectl describe challenge <name>   ← 실패 이유가 여기에 (HTTP 404, DNS 전파 등)
```

## 7. 소스/도구에서 확인하기

- cert-manager: https://cert-manager.io/docs — configuration, troubleshooting
- ACME 챌린지: https://letsencrypt.org/docs/challenge-types/
- rate limit: https://letsencrypt.org/docs/rate-limits/
- trust-manager: https://cert-manager.io/docs/trust/
- 07 복습: 보안 시간선의 신원 축

## 요약 카드

| 질문 | 답 |
|------|----|
| 리소스 체인? | Certificate → CertificateRequest → (Order → Challenge) → Secret |
| HTTP-01 vs DNS-01? | 웹 경로 응답(와일드카드 불가) vs TXT 레코드(와일드카드·내부 도메인 가능) |
| HTTP-01 흔한 실패? | 80→443 리다이렉트, Ingress 라우팅, 방화벽 |
| rate limit 급소? | 중복 인증서 주 5개 — **테스트는 반드시 스테이징 Issuer** |
| 갱신 시점? | notAfter - renewBefore (미지정 시 수명의 2/3 지점) |
| 내부 CA 체인? | SelfSigned → 루트 CA(isCA) → CA Issuer → 리프 |
| 갱신의 완료? | Secret 변경이 아니라 **앱이 새 인증서로 핸드셰이크** (subPath·env 주의) |
| 필수 알람? | expiration 임박 + Ready=False, 챌린지 반복 실패 |
