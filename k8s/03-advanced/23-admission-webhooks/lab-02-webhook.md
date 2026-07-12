# Lab 02 — 진짜 웹훅 배포와 failurePolicy 실험

> CEL로 안 되는 영역(여기서는 단순화된 예로 체험)을 웹훅으로. 핵심 학습은 **TLS 부트스트랩**과 **장애 모드**입니다.

## Step 1. 인증서 준비 — 웹훅의 첫 관문

API 서버는 HTTPS + 신뢰된 CA만 호출합니다. 자가 CA로 해결:

```bash
mkdir -p ~/webhook-lab && cd ~/webhook-lab
# CA + 서버 인증서 (CN과 SAN이 Service DNS와 일치해야 함!)
openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 7 -subj "/CN=webhook-ca"
openssl req -newkey rsa:2048 -nodes -keyout tls.key -out tls.csr \
  -subj "/CN=demo-webhook.webhook.svc" \
  -addext "subjectAltName=DNS:demo-webhook.webhook.svc"
openssl x509 -req -in tls.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out tls.crt -days 7 \
  -copy_extensions copy

kubectl create ns webhook
kubectl create secret tls webhook-tls -n webhook --cert=tls.crt --key=tls.key
```

> 💡 실무에서는 cert-manager가 이 과정(발급+갱신+caBundle 주입)을 전부 자동화합니다 — 웹훅 운영의 사실상 필수 동반자.

## Step 2. 초미니 웹훅 서버 — "team 라벨 없는 Pod 거부"

파이썬 한 파일로 AdmissionReview 규약을 체험합니다:

```bash
cat > webhook.py <<'EOF'
import json, ssl
from http.server import HTTPServer, BaseHTTPRequestHandler

class H(BaseHTTPRequestHandler):
    def do_POST(self):
        review = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        req = review["request"]
        labels = req["object"]["metadata"].get("labels") or {}
        allowed = "team" in labels
        resp = {"apiVersion": "admission.k8s.io/v1", "kind": "AdmissionReview",
                "response": {"uid": req["uid"], "allowed": allowed,
                             "status": {"message": "Pod에 team 라벨 필수 (webhook)"}}}
        body = json.dumps(resp).encode()
        self.send_response(200); self.send_header("Content-Type","application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers()
        self.wfile.write(body)

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain("/certs/tls.crt", "/certs/tls.key")
srv = HTTPServer(("0.0.0.0", 8443), H); srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
print("webhook up"); srv.serve_forever()
EOF
kubectl create configmap webhook-code -n webhook --from-file=webhook.py

cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: demo-webhook, namespace: webhook }
spec:
  replicas: 1                      # 일부러 1개 — 장애 실험용 (실무는 2+!)
  selector: { matchLabels: { app: demo-webhook } }
  template:
    metadata: { labels: { app: demo-webhook, team: platform } }
    spec:
      volumes:
      - { name: certs, secret: { secretName: webhook-tls } }
      - { name: code, configMap: { name: webhook-code } }
      containers:
      - name: server
        image: public.ecr.aws/docker/library/python:3.13-slim
        command: ["python", "/code/webhook.py"]
        ports: [{ containerPort: 8443 }]
        volumeMounts:
        - { name: certs, mountPath: /certs }
        - { name: code, mountPath: /code }
---
apiVersion: v1
kind: Service
metadata: { name: demo-webhook, namespace: webhook }
spec:
  selector: { app: demo-webhook }
  ports: [{ port: 443, targetPort: 8443 }]
EOF
kubectl rollout status deploy/demo-webhook -n webhook
```

## Step 3. 웹훅 등록 (방어 설계 포함)

```bash
CA_BUNDLE=$(base64 -w0 < ca.crt)
cat <<EOF | kubectl apply -f -
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata: { name: team-label-webhook }
webhooks:
- name: team-label.example.com
  clientConfig:
    service: { name: demo-webhook, namespace: webhook, path: /, port: 443 }
    caBundle: $CA_BUNDLE
  rules:
  - apiGroups: [""]
    apiVersions: ["v1"]
    operations: ["CREATE"]
    resources: ["pods"]
  failurePolicy: Fail
  timeoutSeconds: 5
  sideEffects: None
  admissionReviewVersions: ["v1"]
  namespaceSelector:                 # ★ 방어: 실험 ns에만 + 자기 자신/시스템 제외
    matchLabels: { webhook-test: "true" }
EOF
kubectl create ns hook-target && kubectl label ns hook-target webhook-test=true
```

## Step 4. 동작 검증

```bash
kubectl run nolabel --image=public.ecr.aws/docker/library/busybox:stable -n hook-target -- sleep 60
```

예상:
```
Error from server: admission webhook "team-label.example.com" denied the request: Pod에 team 라벨 필수 (webhook)
```

```bash
kubectl run withlabel --image=public.ecr.aws/docker/library/busybox:stable -n hook-target --labels=team=shop -- sleep 60
# → created
kubectl logs -n webhook deploy/demo-webhook | tail -2     # 호출 기록 확인
```

✅ 내가 만든 HTTP 서버가 **API 서버 파이프라인의 일부**가 됐습니다.

## Step 5. 장애 실험 — Fail의 양날

```bash
kubectl scale deploy demo-webhook -n webhook --replicas=0     # 웹훅 사망!
kubectl run victim --image=public.ecr.aws/docker/library/busybox:stable -n hook-target --labels=team=ok -- sleep 60
```

예상 (timeout 5초 후):
```
Error from server (InternalError): ... failed calling webhook ... connect: connection refused
```

✅ **규칙을 지킨 Pod조차 거부됩니다** — 검사관이 없으니 전원 억류(Fail). namespaceSelector 덕에 hook-target만 마비됐지만, rules가 전 ns의 pods였다면 **클러스터의 모든 Pod 생성이** 멈췄을 것입니다 — 노드 복구, 스케일링 포함. 이것이 "웹훅 = 잠재적 SPOF"의 실체.

```bash
# Ignore로 바꾸면? — 통과하지만 검사도 없음 (보안 구멍)
kubectl patch validatingwebhookconfiguration team-label-webhook --type=json \
  -p='[{"op":"replace","path":"/webhooks/0/failurePolicy","value":"Ignore"}]'
kubectl run sneaky --image=public.ecr.aws/docker/library/busybox:stable -n hook-target -- sleep 60   # 라벨 없이도 통과!
kubectl scale deploy demo-webhook -n webhook --replicas=1   # 복구
```

## Step 6. 설계 결론 (가져갈 것)

```
[ ] 검증은 CEL(VAP) 우선 — 웹훅 자체를 줄이는 게 최고의 방어
[ ] 웹훅 필수라면: replicas 2+, PDB, 멀티 AZ
[ ] namespaceSelector로 kube-system/자기 ns 제외 (데드락 방지)
[ ] timeoutSeconds 5 이하, rules 최소 범위
[ ] failurePolicy: 보안 정책=Fail+HA, 편의 기능=Ignore
[ ] cert-manager로 인증서 수명주기 자동화
```

## 정리

```bash
bash cleanup.sh
```
