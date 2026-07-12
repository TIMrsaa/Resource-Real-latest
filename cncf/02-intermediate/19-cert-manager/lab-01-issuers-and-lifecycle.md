# Lab 01 — 리소스 체인을 따라가고, 갱신 타이밍을 계산합니다

Certificate 하나가 Secret이 되기까지의 모든 오브젝트를 관찰하고, 갱신이 언제 일어나는지 실측합니다.

전제: kind, kubectl, helm, openssl.

## Step 1. 클러스터와 cert-manager

```bash
kind create cluster --name certs -q
helm repo add jetstack https://charts.jetstack.io >/dev/null 2>&1
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace \
  --set crds.enabled=true >/dev/null
kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
kubectl -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s

kubectl get crd | grep cert-manager
```

✅ CRD가 리소스 체인을 그대로 보여줍니다: certificates, certificaterequests, orders, challenges, issuers, clusterissuers.

## Step 2. 가장 단순한 Issuer — SelfSigned

```bash
kubectl create ns apps
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: { name: selfsigned }
spec: { selfSigned: {} }
EOF

kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: demo-tls, namespace: apps }
spec:
  secretName: demo-tls
  issuerRef: { name: selfsigned, kind: ClusterIssuer }
  commonName: demo.internal
  dnsNames: ["demo.internal", "demo.apps.svc"]
  duration: 24h                # ★ 짧게 — 갱신을 관찰하기 위해
  renewBefore: 23h             # ★ 발급 1시간 후 갱신 (실험용 극단값)
  privateKey: { algorithm: ECDSA, size: 256, rotationPolicy: Always }
EOF
sleep 10
```

## Step 3. 체인 관찰 — 무엇이 생겼나

```bash
echo "=== Certificate ==="
kubectl -n apps get certificate demo-tls
echo ""
echo "=== CertificateRequest (컨트롤러가 만든 1회성 요청) ==="
kubectl -n apps get certificaterequest
echo ""
echo "=== Secret (결과물) ==="
kubectl -n apps get secret demo-tls -o jsonpath='{.type}'; echo
kubectl -n apps get secret demo-tls -o jsonpath='{.data}' | python3 -c "import json,sys; print('키:', list(json.load(sys.stdin).keys()))"
```

예상: Certificate Ready=True, CertificateRequest 하나, Secret type=`kubernetes.io/tls`에 tls.crt·tls.key. ✅ theory §1의 체인이 오브젝트로.

## Step 4. 인증서 실물 해부

```bash
kubectl -n apps get secret demo-tls -o jsonpath='{.data.tls\.crt}' | base64 -d > /tmp/tls.crt
openssl x509 -in /tmp/tls.crt -noout -subject -issuer -dates -ext subjectAltName 2>/dev/null | head -8

echo ""
echo "=== 갱신 시점 계산 (theory §3) ==="
kubectl -n apps get certificate demo-tls -o jsonpath='{.status.notAfter}'; echo " ← 만료"
kubectl -n apps get certificate demo-tls -o jsonpath='{.status.renewalTime}'; echo " ← 갱신 예정"
python3 - <<'EOF'
import subprocess, datetime
get = lambda p: subprocess.run(["kubectl","-n","apps","get","certificate","demo-tls","-o",f"jsonpath={{{p}}}"],capture_output=True,text=True).stdout
na = get(".status.notAfter"); rt = get(".status.renewalTime")
if na and rt:
    na_d = datetime.datetime.fromisoformat(na.replace("Z","+00:00"))
    rt_d = datetime.datetime.fromisoformat(rt.replace("Z","+00:00"))
    print(f"renewBefore = notAfter - renewalTime = {na_d - rt_d}")
EOF
```

✅ `renewalTime = notAfter - renewBefore`. renewBefore를 지정하지 않으면 duration의 1/3 지점이 됩니다(90일 → 30일 전).

## Step 5. 갱신을 강제 관찰 — 키 회전 확인

```bash
OLD_CRT=$(kubectl -n apps get secret demo-tls -o jsonpath='{.data.tls\.crt}' | md5sum | cut -d' ' -f1)
OLD_KEY=$(kubectl -n apps get secret demo-tls -o jsonpath='{.data.tls\.key}' | md5sum | cut -d' ' -f1)
echo "갱신 전 crt: $OLD_CRT"
echo "갱신 전 key: $OLD_KEY"

# cmctl 없이 갱신 트리거: Issuing 조건을 직접 추가
kubectl -n apps patch certificate demo-tls --type=merge --subresource status \
  -p '{"status":{"conditions":[{"type":"Issuing","status":"True","reason":"ManuallyTriggered","message":"lab","lastTransitionTime":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}]}}' 2>/dev/null || \
  kubectl -n apps delete secret demo-tls   # 대안: Secret 삭제 → 컨트롤러가 재발급

sleep 20
NEW_CRT=$(kubectl -n apps get secret demo-tls -o jsonpath='{.data.tls\.crt}' | md5sum | cut -d' ' -f1)
NEW_KEY=$(kubectl -n apps get secret demo-tls -o jsonpath='{.data.tls\.key}' | md5sum | cut -d' ' -f1)
echo "갱신 후 crt: $NEW_CRT"
echo "갱신 후 key: $NEW_KEY"
[ "$OLD_KEY" != "$NEW_KEY" ] && echo "✅ rotationPolicy: Always — 키도 새로 생성됐다"
```

✅ `rotationPolicy: Always`면 갱신 시 개인키도 새로 만듭니다(권장 — 키 유출의 노출 창을 줄입니다). `Never`면 키를 재사용합니다.

## Step 6. ACME 개념 확인 (실제 발급은 스테이징에서)

```bash
cat <<'EOF'
[HTTP-01 ClusterIssuer 예시]
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: { name: letsencrypt-staging }
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory  # ★ 반드시 스테이징부터
    email: ops@example.com
    privateKeySecretRef: { name: le-staging-account }
    solvers:
      - http01: { ingress: { ingressClassName: nginx } }

[DNS-01 (와일드카드·내부 도메인)]
    solvers:
      - dns01:
          route53:
            region: ap-northeast-2
            # IRSA로 권한 (eks) — 액세스 키 하드코딩 금지 (cicd 22)
        selector: { dnsZones: ["example.com"] }

★ rate limit (theory §2):
   중복 인증서 주 5개 — 테스트를 프로덕션 서버로 하면 일주일 잠깁니다
   실패 검증도 카운트됩니다(시간당 5회)

★ 발급 진행 상황 디버깅 순서:
   kubectl describe certificate  → CertificateRequest → Order → Challenge
   kubectl describe challenge <name>   ← 실패 이유가 여기에 있습니다
     "404" → HTTP-01 라우팅 문제 (80→443 리다이렉트가 범인인 경우 많음)
     "propagation" → DNS-01 전파 대기
EOF
```

## Step 7. 관측 — 만료 알람의 재료

```bash
kubectl -n cert-manager port-forward svc/cert-manager 9402:9402 >/dev/null 2>&1 &
sleep 3
curl -s http://localhost:9402/metrics 2>/dev/null | grep -E "^certmanager_certificate_(expiration|ready)" | head -4
kill %1 2>/dev/null || true

cat <<'EOF'

필수 알람 (theory §6):
  # 7일 내 만료인데 Ready가 아님 → 갱신 실패
  (certmanager_certificate_expiration_timestamp_seconds - time()) < 7*24*3600
    and certmanager_certificate_ready_status{condition="True"} == 0

  # 챌린지 반복 실패 (rate limit 소진 위험)
  increase(certmanager_http_acme_client_request_count{status!="200"}[1h]) > 5
EOF
```

## Step 8. 산출물

```markdown
# cert-manager 리소스 체인
Certificate(선언) → CertificateRequest(CSR) → [ACME: Order → Challenge] → Secret(tls.crt/key)
- Issuer(ns) vs ClusterIssuer(전역), 자격증명 Secret은 cert-manager 네임스페이스
- renewalTime = notAfter - renewBefore (미지정 시 duration의 2/3 지점)
- rotationPolicy: Always 권장 (갱신 시 키도 새로)
- 디버깅: Certificate → CR → Order → Challenge 순으로 describe
- 알람: 만료 임박 + Ready=False
```

## 정리

lab-02에서 계속. 유지.
