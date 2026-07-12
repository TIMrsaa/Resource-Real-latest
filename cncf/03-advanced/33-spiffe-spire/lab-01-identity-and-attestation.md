# Lab 01 — SPIFFE ID·SVID와 어테스테이션

SPIRE를 설치하고, 워크로드가 "주장"이 아니라 "증명"으로 신원을 받는 것을 확인합니다.

전제: kind, kubectl, helm.

## Step 1. 클러스터와 SPIRE

```bash
kind create cluster --name spire -q

helm repo add spiffe https://spiffe.github.io/helm-charts-hardened >/dev/null 2>&1
helm upgrade --install spire-crds spiffe/spire-crds -n spire-server --create-namespace >/dev/null
helm upgrade --install spire spiffe/spire -n spire-server \
  --set global.spire.trustDomain=example.org \
  --wait --timeout 300s >/dev/null 2>&1 || \
  echo "(설치에 시간 소요 — kubectl -n spire-server get pods 로 확인)"

kubectl -n spire-server get pods 2>/dev/null | head -5
kubectl get ns | grep spire
```

## Step 2. 아키텍처 — Server와 Agent

```bash
echo "=== SPIRE Server (중앙) ==="
kubectl -n spire-server get statefulset 2>/dev/null | grep server
echo ""
echo "=== SPIRE Agent (노드당 DaemonSet) ==="
kubectl -n spire-system get ds 2>/dev/null | grep agent || kubectl -n spire-server get ds | grep agent

cat <<'EOF'
역할 (theory §2):
  Server: SVID 발급, Trust Bundle, 등록 항목, 노드 어테스테이션 검증
  Agent(노드당): 노드 증명 → 워크로드 증명 → Workload API로 SVID 전달
EOF
```

## Step 3. Trust Bundle — 신뢰 앵커

```bash
SERVER=$(kubectl -n spire-server get pod -l app.kubernetes.io/name=server -o name 2>/dev/null | head -1)
[ -z "$SERVER" ] && SERVER=$(kubectl -n spire-server get pod | grep server | head -1 | awk '{print $1}' | sed 's/^/pod\//')

echo "=== Trust Bundle (SVID 검증의 루트 — 19의 CA 번들) ==="
kubectl -n spire-server exec $SERVER -c spire-server -- \
  /opt/spire/bin/spire-server bundle show 2>/dev/null | head -5 || \
  echo "(spire-server bundle show — trust domain의 루트 CA)"
```

## Step 4. 등록 항목 — "어떤 속성에 어떤 신원을"

```bash
cat <<'EOF'
=== 등록 항목(registration entry) (theory §2) ===
Server에 "이런 속성의 워크로드에 이 SPIFFE ID를 줘라"를 등록:

spire-server entry create \
  -spiffeID spiffe://example.org/ns/prod/sa/payment \
  -parentID spiffe://example.org/spire/agent/k8s_psat/... \
  -selector k8s:ns:prod \
  -selector k8s:sa:payment

의미:
  "prod 네임스페이스의 payment SA로 실행되는 워크로드에게
   spiffe://example.org/ns/prod/sa/payment 신원을 발급"
  → 셀렉터(속성)가 곧 신원의 조건
EOF

# 실제 등록 항목 조회
kubectl -n spire-server exec $SERVER -c spire-server -- \
  /opt/spire/bin/spire-server entry show 2>/dev/null | head -12 || \
  echo "(spire-server entry show)"
```

## Step 5. 어테스테이션 — 주장이 아니라 증명

```bash
cat <<'EOF'
=== 워크로드는 자기 신원을 '주장'하지 않습니다 (theory §3) ===

전통적(취약):
  앱: "나는 payment 서비스야" (API 키를 제시)
  → API 키 유출 = 누구나 payment 행세

SPIFFE(증명):
  앱: Workload API 소켓 호출 (아무 주장 없음)
  Agent: 그 프로세스의 커널 속성을 확인
    - 어느 Pod인가요? (Pod의 SA, namespace, labels)
    - 커널이 그 프로세스의 실체를 검증 (uid, cgroup...)
  → Server의 등록 항목과 대조 → 조건 맞으면 SVID 발급
  → 앱은 "내가 누구다"라고 거짓말할 수 없습니다 (커널이 증명)

노드 어테스테이션 (그 노드 자체가 진짜인가):
  k8s_psat: K8s Projected SA Token → API 서버가 검증
  aws_iid: AWS Instance Identity Doc → AWS가 서명
  → 신뢰의 뿌리가 플랫폼(K8s·클라우드)에 (theory §4)
EOF

# 노드 어테스테이션 방식 확인
kubectl -n spire-server exec $SERVER -c spire-server -- \
  /opt/spire/bin/spire-server agent list 2>/dev/null | head -6 || \
  echo "(spire-server agent list — 증명된 노드들)"
```

## Step 6. SVID 발급 흐름 정리

```bash
cat <<'EOF'
=== SVID 발급 전체 흐름 (theory §2·§3) ===
1. Agent 시작 → 노드 어테스테이션 (k8s_psat/aws_iid)
   → Server가 노드를 검증하고 노드 SVID 발급
2. 워크로드가 Workload API 소켓 호출
   → Agent가 그 프로세스의 커널 속성 수집 (Pod SA·ns·labels)
3. Agent가 Server에 조회 → 등록 항목의 셀렉터와 대조
   → 맞으면 워크로드 SVID 발급
4. Agent가 워크로드에 SVID 전달 (소켓)
   → 짧은 수명(1h), 자동 갱신

★ 핵심: 최초 시크릿이 없습니다
  플랫폼의 기존 신뢰(K8s가 SA를 아는 것)에서 신원이 파생 (07의 OIDC 통찰)
EOF
```

## Step 7. 산출물

```markdown
# SPIFFE/SPIRE 신원 카드
- SPIFFE ID: spiffe://trust-domain/path (24 Istio mTLS의 신원)
- SVID: 검증 가능한 신원 문서 (X.509/JWT, 각자의 인증서)
- Trust Bundle: SVID 검증의 루트 (19의 CA 번들)
- 등록 항목: "이런 속성(셀렉터)에 이 SPIFFE ID"
- 어테스테이션: 주장 아니라 플랫폼 속성으로 증명 (위조 불가)
  - 노드: k8s_psat/aws_iid (플랫폼이 노드를 증명)
  - 워크로드: k8s selector (커널이 프로세스를 증명)
- 최초 시크릿 없음 (플랫폼 기존 신뢰에서 파생 — 07)
```

## 정리

lab-02에서 부트스트랩과 통합을 다룹니다. 유지.
