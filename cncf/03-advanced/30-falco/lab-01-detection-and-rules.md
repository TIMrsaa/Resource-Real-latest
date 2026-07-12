# Lab 01 — 탐지 재현과 규칙 읽기·작성

Falco를 설치하고, admission이 못 잡는 런타임 침해 신호를 탐지하는 것을 확인한 뒤, 규칙을 읽고 커스텀 규칙을 만듭니다.

전제: kind, kubectl, helm. eBPF 드라이버가 안 뜨면 커널 지원 확인.
⚠️ 방어 목적 실습 — 탐지 대상 행위는 격리된 실습 클러스터에서만.

## Step 1. 클러스터와 Falco

```bash
kind create cluster --name falco -q

helm repo add falcosecurity https://falcosecurity.github.io/charts >/dev/null 2>&1
helm install falco falcosecurity/falco -n falco --create-namespace \
  --set driver.kind=modern_ebpf \
  --set tty=true \
  --set falcosidekick.enabled=true >/dev/null
kubectl -n falco rollout status ds/falco --timeout=300s 2>/dev/null || \
  kubectl -n falco get pods
```

(eBPF 드라이버가 안 뜨면 `--set driver.kind=ebpf` 시도, 그래도 안 되면 규칙 파일 관찰로 대체.)

## Step 2. 탐지 대상 앱

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: victim
  labels: { run: victim }
spec:
  containers:
    - name: victim
      image: nginx
EOF
kubectl wait --for=condition=ready pod/victim --timeout=120s
```

## Step 3. 탐지 재현 ① — 컨테이너 내 셸 (07 사고 사례의 첫 신호)

```bash
# 침해의 고전 신호: 정상 컨테이너 안에서 셸 실행
kubectl exec victim -- bash -c "echo 'attacker in container'" 2>/dev/null || \
  kubectl exec victim -- sh -c "echo 'attacker in container'"
sleep 5

echo "=== Falco의 탐지 ==="
kubectl -n falco logs ds/falco --tail=50 2>/dev/null | \
  grep -iE "shell|Terminal|spawned" | head -3
```

예상: `Terminal shell in container (user=... container=victim proc=bash...)`. ✅ **admission을 통과한 정상 Pod의 셸 실행을 시스템콜(execve)에서 잡았습니다**(theory §2) — 07 사고 사례가 놓쳤던 그 순간.

## Step 4. 탐지 재현 ② — 민감 파일 접근

```bash
kubectl exec victim -- cat /etc/shadow 2>/dev/null || true
sleep 5
echo "=== 민감 파일 접근 탐지 ==="
kubectl -n falco logs ds/falco --tail=50 2>/dev/null | \
  grep -iE "sensitive|shadow|/etc" | head -3
```

예상: `Read sensitive file` 류 경보. ✅ `open(/etc/shadow)` 시스템콜을 규칙이 잡았습니다.

## Step 5. 규칙 읽기 — 무엇을 이상으로 정의했나

```bash
echo "=== Terminal shell 규칙의 구조 ==="
kubectl -n falco exec ds/falco -- cat /etc/falco/falco_rules.yaml 2>/dev/null | \
  grep -A12 "rule: Terminal shell in container" | head -14

cat <<'EOF'

규칙 구성 (theory §3):
  condition: spawned_process and container and shell_procs and proc.tty != 0 ...
    → "컨테이너 안에서 셸 프로세스가 tty로 실행"
  output: 경보 메시지 (%container.name 등 필드 치환)
  priority: NOTICE
  tags: [container, shell, mitre_execution]  ← MITRE ATT&CK 매핑

재사용 (macro·list):
  spawned_process = evt.type in (execve, execveat) and evt.dir = <
  shell_binaries = [bash, sh, zsh, ...]
  → 규칙을 조립 (20의 플러그인, 23의 필터와 같은 계열)
EOF
```

## Step 6. 커스텀 규칙 — 우리 환경의 이상 정의

```bash
kubectl -n falco create configmap custom-rules --from-literal=custom_rules.yaml='
- rule: Unexpected outbound connection to crypto pool
  desc: Detect connection to known crypto mining ports
  condition: >
    outbound and container
    and fd.sport != 0
    and (fd.dport in (3333, 4444, 5555, 7777))
  output: >
    Suspicious outbound connection (container=%container.name
    connection=%fd.name proc=%proc.cmdline)
  priority: WARNING
  tags: [network, mitre_impact, cryptomining]

- rule: Service account token accessed
  desc: Detect reads of the K8s service account token
  condition: >
    open_read and container
    and fd.name contains "/var/run/secrets/kubernetes.io/serviceaccount/token"
  output: >
    SA token accessed (container=%container.name proc=%proc.cmdline user=%user.name)
  priority: WARNING
  tags: [k8s, secrets, mitre_credential_access]
' 2>/dev/null

cat <<'EOF'
→ 커스텀 규칙 배포:
  helm upgrade falco ... --set-file customRules."custom_rules\.yaml"=custom_rules.yaml
  또는 falcoctl로 규칙 관리

우리 환경의 "이상"을 정의:
  - 크립토 마이닝 포트로의 아웃바운드 (07 사고: 채굴이 청구서로 발견됨)
  - 서비스 어카운트 토큰 접근 (측면 이동의 전조)
  → 07 사고 사례의 공격 단계들을 규칙으로 (사후 학습이 규칙이 됩니다)
EOF
```

## Step 7. 튜닝 — 오탐과의 싸움

```bash
cat <<'EOF'
=== 오탐 관리 (theory §4) ===
문제: 기본 규칙이 정상 동작을 잡습니다
  예: 배포 스크립트의 셸, 모니터링 에이전트의 /proc 읽기, 헬스체크

튜닝:
  exceptions: 규칙에 예외
    - rule: Terminal shell in container
      exceptions:
        - name: known_shells
          fields: [container.image.repository, proc.cmdline]
          values:
            - [my-debug-image, ...]     # 이 이미지의 셸은 정상
  priority 조정: 노이즈 규칙 하향
  비활성: 우리 환경에 무관한 규칙 끄기

★ 06의 알림 설계 원리:
  대응 가능한 경보만, 오탐률 관리, 심각도=영향×긴급도
  튜닝 없는 Falco = 노이즈 발생기 → 아무도 안 봄 (07 사고의 재현)
EOF
```

## Step 8. 산출물

```markdown
# Falco 탐지 카드
- 자리: 07 시간선의 실행 중(탐지) — admission 통과 후 침해를 봅니다
- 소스: 시스템콜(execve/open/connect...)을 eBPF로 가로채기
- 규칙: condition(이상 정의)/output/priority/tags + macro·list 조립
- 커스텀: 우리 환경·과거 사고의 공격 단계를 규칙으로
- 튜닝: 오탐 관리(exceptions) — 없으면 노이즈 발생기
- 탐지 예: 컨테이너 내 셸, 민감 파일, SA 토큰, 크립토 포트
```

## 정리

lab-02에서 대응과 비교를 다룹니다. 유지.
