# Lab 02 — 내부 CA 체계와 회전의 마지막 홉

사설 PKI를 세우고, 갱신된 인증서가 앱에 실제로 반영되는지(또는 안 되는지) 확인합니다 — cicd 22의 전파 문제가 여기서 재현됩니다.

전제: lab-01의 클러스터(kind: certs).

## Step 1. 루트 CA 만들기 — SelfSigned → CA 체인

```bash
kubectl apply -f - <<'EOF'
# ① 자기서명 Issuer (루트 CA를 만들기 위한 부트스트랩)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: { name: selfsigned }
spec: { selfSigned: {} }
---
# ② 루트 CA 인증서 (isCA: true)
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: internal-root, namespace: cert-manager }
spec:
  isCA: true
  commonName: internal-root-ca
  secretName: internal-root-ca
  issuerRef: { name: selfsigned, kind: ClusterIssuer }
  privateKey: { algorithm: ECDSA, size: 256 }
  duration: 87600h        # 10년
  renewBefore: 8760h
---
# ③ 그 CA로 서명하는 Issuer
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: { name: internal-ca }
spec:
  ca: { secretName: internal-root-ca }
EOF
sleep 15
kubectl -n cert-manager get certificate internal-root
kubectl get clusterissuer
```

✅ 3단 체인(theory §4). 이제 `internal-ca`로 발급하는 모든 인증서는 같은 루트를 갖습니다 — mTLS의 신뢰 앵커.

```bash
kubectl -n cert-manager get secret internal-root-ca -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/ca.crt
openssl x509 -in /tmp/ca.crt -noout -subject -ext basicConstraints 2>/dev/null
echo "→ CA:TRUE 이면 서명 권한이 있는 인증서"
```

⚠️ **루트 CA 개인키가 클러스터 Secret에 있습니다** — 클러스터 침해 = CA 침해. 프로덕션은 Vault/AWS PCA Issuer 검토(07의 신뢰 경계).

## Step 2. 리프 인증서 발급 — 짧은 수명으로

```bash
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: web-tls, namespace: apps }
spec:
  secretName: web-tls
  issuerRef: { name: internal-ca, kind: ClusterIssuer }
  commonName: web.apps.svc
  dnsNames: ["web.apps.svc", "web.apps.svc.cluster.local"]
  duration: 2h              # 짧게 (회전 실습)
  renewBefore: 1h50m        # 발급 10분 후 갱신 시도
  privateKey: { rotationPolicy: Always }
EOF
sleep 15
kubectl -n apps get certificate web-tls
kubectl -n apps get secret web-tls -o jsonpath='{.data.ca\.crt}' | base64 -d | head -1
echo "→ ca.crt도 함께 들어갑니다 (클라이언트가 체인 검증에 사용)"
```

## Step 3. 전파 실험 — 세 가지 마운트 방식

```bash
kubectl -n apps apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: consumer }
spec:
  containers:
    - name: c
      image: busybox
      command: ["sh","-c","while true; do sleep 10; done"]
      env:
        - name: CERT_FROM_ENV                      # ❌ 방식 A: env (재시작 전까지 고정)
          valueFrom: { secretKeyRef: { name: web-tls, key: tls.crt } }
      volumeMounts:
        - { name: certs, mountPath: /etc/tls }     # ✅ 방식 B: 일반 볼륨 (kubelet이 갱신)
        - { name: certs, mountPath: /etc/sub/tls.crt, subPath: tls.crt }  # ❌ 방식 C: subPath
  volumes:
    - name: certs
      secret: { secretName: web-tls }
EOF
kubectl -n apps wait --for=condition=ready pod/consumer --timeout=120s

echo "=== 초기 해시 ==="
echo "볼륨(B):  $(kubectl -n apps exec consumer -- md5sum /etc/tls/tls.crt | cut -d' ' -f1)"
echo "subPath(C): $(kubectl -n apps exec consumer -- md5sum /etc/sub/tls.crt | cut -d' ' -f1)"
echo "env(A):   $(kubectl -n apps exec consumer -- sh -c 'echo "$CERT_FROM_ENV"' | md5sum | cut -d' ' -f1)"
```

## Step 4. 강제 갱신 후 — 무엇이 바뀌었나

```bash
kubectl -n apps delete secret web-tls   # 컨트롤러가 즉시 재발급
sleep 25
kubectl -n apps get certificate web-tls -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'; echo

echo ""
echo "kubelet의 볼륨 갱신을 기다립니다 (최대 ~1분)..."
sleep 70

echo "=== 갱신 후 해시 ==="
echo "볼륨(B):    $(kubectl -n apps exec consumer -- md5sum /etc/tls/tls.crt | cut -d' ' -f1)  ← 바뀌어야 정상"
echo "subPath(C): $(kubectl -n apps exec consumer -- md5sum /etc/sub/tls.crt | cut -d' ' -f1)  ← 안 바뀝니다!"
echo "env(A):     $(kubectl -n apps exec consumer -- sh -c 'echo "$CERT_FROM_ENV"' | md5sum | cut -d' ' -f1)  ← 안 바뀝니다!"
```

예상: 볼륨(B)만 갱신, subPath(C)와 env(A)는 옛 값. ✅ **cicd 22에서 배운 전파 문제가 인증서에서 그대로 재현**됩니다(theory §5). 그리고 이것이 "인증서를 갱신했는데 앱이 여전히 옛 것을 쓴다"의 정체입니다.

## Step 5. 마지막 홉 — 앱이 새 인증서를 실제로 쓰게

```bash
cat <<'EOF'
파일이 갱신돼도 앱이 시작 시 한 번만 읽었다면 메모리의 인증서는 옛 것입니다.

해법 스펙트럼:
  ① 앱이 파일 변경 감지 후 리로드
     nginx: SIGHUP / envoy: SDS(동적 갱신) / Go: fsnotify + tls.Config.GetCertificate
  ② Reloader 등으로 Secret 변경 시 롤링 재시작 (범용, 짧은 재시작 감수)
     annotation: reloader.stakater.com/auto: "true"
  ③ Ingress 컨트롤러: 대개 자동 감지·리로드 (구현별 확인)
  ④ 서비스 메시(eks 20): SDS로 무중단 회전 — 사이드카가 처리

★ "갱신 완료"의 정의를 바꿔라:
  Secret이 바뀐 것(X) → 앱이 새 인증서로 TLS 핸드셰이크하는 것(O)
  검증: openssl s_client -connect <svc>:443 로 서버 인증서의 notAfter 확인
EOF

# 검증 방법 예시
kubectl -n apps exec consumer -- sh -c '
  echo "실제 서비스 검증 예시:"
  echo "  openssl s_client -connect web.apps.svc:443 -servername web.apps.svc </dev/null 2>/dev/null | openssl x509 -noout -dates"
' 2>/dev/null || true
```

## Step 6. trust-manager — 루트 CA 번들 배포

```bash
cat <<'EOF'
문제: 내부 CA로 서명한 인증서를 검증하려면 클라이언트가 루트 CA를 알아야 합니다
      → 모든 네임스페이스에 ca.crt를 뿌려야 하나요?

trust-manager(cert-manager 자매 프로젝트):
apiVersion: trust.cert-manager.io/v1alpha1
kind: Bundle
metadata: { name: internal-trust }
spec:
  sources:
    - useDefaultCAs: true                        # 공개 CA 번들
    - secret: { name: internal-root-ca, key: tls.crt }   # 우리 루트 CA
  target:
    configMap: { key: ca-bundle.crt }
    namespaceSelector: { matchLabels: { trust: "enabled" } }

→ 라벨이 붙은 모든 네임스페이스에 ConfigMap으로 번들 배포·동기화
EOF
```

## Step 7. 산출물

```markdown
# cert-manager 운영 카드
## 발급
- 공개: ACME(HTTP-01 / DNS-01) — 스테이징에서 먼저! rate limit(중복 주 5개)
- 사설: SelfSigned → 루트 CA(isCA) → CA Issuer → 리프
- 루트 CA 키가 클러스터 Secret에 있으면 클러스터 침해 = CA 침해 → Vault/PCA 검토

## 갱신
- renewalTime = notAfter - renewBefore (기본: duration의 2/3)
- rotationPolicy: Always (키도 회전)

## 전파 (실무 급소)
- ✅ 일반 볼륨 마운트: kubelet이 갱신
- ❌ subPath 마운트: 갱신 안 됨
- ❌ env 주입: 재시작 전까지 옛 값
- 앱이 파일을 다시 읽는가요? (SIGHUP·SDS·fsnotify·Reloader)
- "갱신 완료" = 앱이 새 인증서로 핸드셰이크 (openssl s_client로 검증)

## 관측
- certmanager_certificate_expiration_timestamp_seconds
- 알람: 7일 내 만료 + Ready=False / 챌린지 반복 실패
```

## 정리

```bash
bash cleanup.sh
```
