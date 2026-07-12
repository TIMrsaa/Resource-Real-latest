# Lab 02 — 문지기와 CCTV: Kyverno 예방 + Falco 탐지

시간선의 두 지점을 나란히 만집니다 — 하나는 나쁜 것을 못 들어오게, 하나는 들어온 것이 나빠지면 알아채게.

전제: kind, kubectl, helm. 메모리 6GB+.

## Step 1. 클러스터

```bash
kind create cluster --name security -q
```

## Step 2. 문지기 — Kyverno admission 정책

```bash
helm repo add kyverno https://kyverno.github.io/kyverno >/dev/null 2>&1
helm install kyverno kyverno/kyverno -n kyverno --create-namespace >/dev/null
kubectl -n kyverno wait --for=condition=ready pod -l app.kubernetes.io/component=admission-controller --timeout=180s

# 정책: 컨테이너는 non-root, latest 태그 금지 (cicd 04·21의 규율을 게이트로)
kubectl apply -f - <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata: { name: baseline-hardening }
spec:
  rules:
    - name: no-latest-tag
      match: { any: [{ resources: { kinds: [Pod] } }] }
      validate:
        failureAction: Enforce
        message: "latest 태그 금지 — 다이제스트 또는 명시 태그 (cicd 04)"
        pattern:
          spec:
            containers:
              - image: "!*:latest"
    - name: require-non-root
      match: { any: [{ resources: { kinds: [Pod] } }] }
      validate:
        failureAction: Enforce
        message: "runAsNonRoot: true 필요"
        pattern:
          spec:
            =(securityContext):
              =(runAsNonRoot): "true"
            containers:
              - =(securityContext):
                  =(runAsNonRoot): "true"
EOF
sleep 5
```

## Step 3. 게이트 동작 확인 — 예방의 실감

```bash
# ① 위반 Pod → 거절되어야 정상
kubectl run bad --image=nginx:latest 2>&1 | tail -2

# ② 준수 Pod → 통과
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: good }
spec:
  securityContext: { runAsNonRoot: true, runAsUser: 1000 }
  containers:
    - name: app
      image: nginxinc/nginx-unprivileged:1.27
      securityContext: { runAsNonRoot: true }
EOF
kubectl get pod good
```

예상: ①은 admission 거절(정책 메시지 출력), ②는 생성. ✅ **배포 시점 방어** — 나쁜 것이 클러스터에 아예 못 들어옵니다(k8s 34·cicd 21의 그 게이트). 그러나 이 문지기는 통과한 후를 보지 않습니다:

```bash
echo "질문: good Pod가 실행 중 침해당하면? → Kyverno는 이미 통과시켰습니다. 다음 층이 필요합니다."
```

## Step 4. CCTV — Falco 런타임 탐지

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null 2>&1
helm install falco falcosecurity/falco -n falco --create-namespace \
  --set driver.kind=modern_ebpf --set tty=true >/dev/null
kubectl -n falco rollout status ds/falco --timeout=300s 2>/dev/null || \
  kubectl -n falco get pods
```

(kind 환경에서 eBPF 드라이버가 안 뜨면 `--set driver.kind=ebpf` 또는 호스트 커널 지원 확인 — 실패해도 Step 5의 개념 확인은 로그 대신 규칙 파일로 대체 가능.)

## Step 5. 침해 흉내 — 탐지가 울리는 순간

```bash
# 정상 통과했던 Pod에서 "컨테이너 안에서 셸 실행" (침해의 고전 신호)
kubectl exec good -- sh -c "cat /etc/shadow 2>/dev/null; id" || true
sleep 5

# Falco의 경보 확인
kubectl -n falco logs ds/falco --tail=40 2>/dev/null | \
  grep -iE "Warning|Notice|shell|sensitive|spawned" | head -5
```

예상: `Terminal shell in container` 또는 `Read sensitive file` 류의 경보 — **admission을 통과한 정상 Pod의 이상 행위**를 시스템콜 수준에서 잡았습니다. ✅ theory §5의 결론: 문지기는 입장을, CCTV는 장내를 봅니다.

```bash
# 규칙의 실체 확인 — Falco는 "무엇을 이상으로 볼지"의 규칙 집합
kubectl -n falco exec ds/falco -- sh -c "ls /etc/falco/ && grep -A3 'Terminal shell in container' /etc/falco/falco_rules.yaml | head -6" 2>/dev/null | head -12
```

## Step 6. 한계 확인 — Falco는 차단하지 않습니다

```bash
cat <<'EOF'
Falco의 경계 (theory §5):
- 탐지·경보이지 차단이 아닙니다 — 셸은 이미 실행됐습니다
- 대응(response)은 별도 설계: 경보 → 알림(Slack/PagerDuty) → 자동 격리(NetworkPolicy 주입·Pod 삭제)
- Falcosidekick 등으로 경보를 액션에 연결
- 강제(enforcement)를 원하면: Tetragon/KubeArmor(LSM·eBPF 강제) 또는 seccomp/AppArmor 프로파일(예방 층)
→ "탐지 도구를 깔았으니 안전"이 아니라, 경보에 반응할 사람·자동화가 있어야 방어입니다
EOF
```

## Step 7. 산출물 — 두 층의 대비표

```markdown
# 오늘 확인한 시간선 두 지점
| | Kyverno (배포 시점) | Falco (실행 중) |
|---|---|---|
| 성격 | 예방 (문지기) | 탐지 (CCTV) |
| 대상 | API 요청(Pod 스펙) | 시스템콜(실제 행위) |
| 결과 | 거절 (안 들어옴) | 경보 (이미 일어남) |
| 사각 | 통과 후의 모든 것 | 차단 불가, 규칙 밖 행위 |
| 결론 | 둘 다 필요 — 방어는 층의 곱 (cicd 21의 명제) |
```

## 정리

```bash
bash cleanup.sh
```
