# Lab 02 — GitOps 시크릿 3해법을 한 클러스터에서 비교

sealed-secrets, SOPS, External Secrets Operator를 같은 시크릿으로 돌려보고 "진실이 어디 있는가"의 차이를 몸으로 확인합니다.

전제: kind, kubectl, helm, sops+age(`brew install sops age`), kubeseal(`brew install kubeseal`).

## Step 0. 클러스터와 공통 시크릿

```bash
kind create cluster --name secrets -q
SECRET_VALUE="db-pass-$(date +%s)"
echo "실습 시크릿 값: $SECRET_VALUE"
```

## Step 1. sealed-secrets — 클러스터만 여는 상자

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets >/dev/null 2>&1
helm install sealed sealed-secrets/sealed-secrets -n kube-system >/dev/null
kubectl -n kube-system wait --for=condition=ready pod -l app.kubernetes.io/name=sealed-secrets --timeout=120s

# 평문 Secret → 컨트롤러 공개키로 암호화 → Git에 넣을 수 있는 SealedSecret
kubectl create secret generic db --from-literal=password="$SECRET_VALUE" \
  --dry-run=client -o yaml > plain.yaml
kubeseal --controller-name=sealed --controller-namespace=kube-system \
  -o yaml < plain.yaml > sealed.yaml
rm plain.yaml                              # 평문은 즉시 삭제

grep -A3 "encryptedData" sealed.yaml | head -4   # 통암호문 — diff 리뷰 불가 확인
kubectl apply -f sealed.yaml
sleep 3
kubectl get secret db -o jsonpath='{.data.password}' | base64 -d; echo " ← 복호화됨"
```

예상: 컨트롤러가 SealedSecret을 풀어 Secret 생성. ✅ **sealed.yaml은 Git에 커밋 가능**(암호문) — 단 개인키가 이 클러스터에 있습니다:

```bash
# DR 관점(k8s 36!): 이 키를 백업 안 하면 클러스터 재구축 시 모든 SealedSecret이 쓰레기
kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o name
echo "→ 이 키의 백업이 sealed-secrets 운영의 급소"
```

## Step 2. SOPS — 값만 암호화, diff가 삽니다

```bash
age-keygen -o age.key 2>/dev/null
PUB=$(grep -o "age1.*" age.key)

cat > sops-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata: { name: db-sops }
stringData: { password: "$SECRET_VALUE", host: "db.internal" }
EOF
sops --encrypt --age "$PUB" --encrypted-regex '^(data|stringData)$' \
  sops-secret.yaml > sops-secret.enc.yaml
rm sops-secret.yaml

cat sops-secret.enc.yaml | head -8
```

예상: `password: ENC[AES256_GCM,...]` — **키 이름(password, host)은 평문, 값만 암호문**. ✅ PR에서 "password 값이 바뀌었다"가 diff로 보입니다 — sealed의 통암호문과 결정적 차이. 복호화·적용:

```bash
SOPS_AGE_KEY_FILE=age.key sops --decrypt sops-secret.enc.yaml | kubectl apply -f -
kubectl get secret db-sops -o jsonpath='{.data.password}' | base64 -d; echo " ← 복호화됨"
echo "실무: 이 복호화를 CD가 수행 — Flux는 내장(spec.decryption), age 대신 KMS면 IAM으로 접근 제어"
```

## Step 3. External Secrets Operator — Git에는 포인터만

```bash
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1
helm install eso external-secrets/external-secrets -n external-secrets --create-namespace >/dev/null
kubectl -n external-secrets wait --for=condition=ready pod -l app.kubernetes.io/name=external-secrets --timeout=180s

# 실습용 Fake 스토어 (실전: AWS Secrets Manager/Vault — 인증은 IRSA/OIDC!)
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata: { name: store }
spec:
  provider:
    fake:
      data:
        - key: prod/db-password
          value: "$SECRET_VALUE"
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata: { name: db-eso }
spec:
  refreshInterval: 15s
  secretStoreRef: { name: store, kind: SecretStore }
  target: { name: db-eso }
  data:
    - secretKey: password
      remoteRef: { key: prod/db-password }
EOF
sleep 5
kubectl get secret db-eso -o jsonpath='{.data.password}' | base64 -d; echo " ← 스토어에서 동기화됨"
```

**여기서 핵심 관찰** — 위 YAML 어디에도 시크릿 값이 없습니다(SecretStore의 fake만 실습용 예외). ✅ Git에 커밋되는 것은 **참조**("스토어의 prod/db-password를 가져와라")뿐 — 진실은 스토어에 있습니다.

## Step 4. 순환 비교 — 세 방식의 운명이 갈립니다

```bash
NEW_VALUE="rotated-$(date +%s)"

# ESO: 스토어만 갱신 (실전이면 ASM/Vault에서 한 번) → Git 커밋 불필요
kubectl patch secretstore store --type=merge -p \
  "{\"spec\":{\"provider\":{\"fake\":{\"data\":[{\"key\":\"prod/db-password\",\"value\":\"$NEW_VALUE\"}]}}}}"
sleep 20
kubectl get secret db-eso -o jsonpath='{.data.password}' | base64 -d; echo " ← ESO: 자동 반영 ✅"

cat <<'EOF'
sealed-secrets 순환: 새 값 재암호화(kubeseal) → Git 커밋 → sync   (커밋 필요)
SOPS 순환:          새 값 재암호화(sops)     → Git 커밋 → sync   (커밋 필요)
ESO 순환:           스토어에서 한 번 갱신     → refreshInterval 내 자동 (커밋 불필요) ★
단, 셋 다 남는 숙제: Pod까지의 전파 — env 주입이면 재시작 필요 (theory §5)
EOF
```

## Step 5. 결정표 완성 — 우리 조직이라면

```markdown
# GitOps 시크릿 선택 (lab에서 확인한 것)
- 외부 스토어를 이미 운영 (ASM/Vault)     → ESO — 순환·감사 중앙화, 멀티클러스터 자연
- 스토어 없음 + 단일 클러스터 + 소규모    → sealed-secrets — 단 개인키 백업이 DR 급소
- 스토어 없음 + diff 리뷰 중시 + 멀티     → SOPS(KMS/age) — 값 단위 diff, 복호화 자격 배포 설계 필요
- 어느 쪽이든: 값의 "수명 줄이기"(Vault 동적)가 먼저입니다 — 도구는 남는 것의 관리일 뿐
```

## 정리

```bash
bash cleanup.sh
```
