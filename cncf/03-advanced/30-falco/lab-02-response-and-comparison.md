# Lab 02 — 경보를 대응으로 잇기, 그리고 Tetragon·강제와 비교

탐지는 경보일 뿐입니다 — 그것을 액션으로 잇고, Falco가 22의 Tetragon·seccomp와 어떻게 다른지 자리를 정합니다.

전제: lab-01의 클러스터(kind: falco), Falcosidekick 설치됨.

## Step 1. Falcosidekick — 경보의 팬아웃

```bash
kubectl -n falco get pods | grep falcosidekick
echo ""
echo "=== Falcosidekick가 하는 일 (theory §5) ==="
cat <<'EOF'
Falco 출력 → Falcosidekick → 여러 대상:
  알림: Slack, Teams, PagerDuty, email, Discord
  저장: Elasticsearch, Loki(14), S3, Kafka
  메트릭: Prometheus(11) — falcosidekick_outputs_total
  자동 대응: Response Engine (경보 → 함수/워크플로)

설정 예 (helm values):
  falcosidekick:
    config:
      slack:
        webhookurl: "https://hooks.slack.com/..."
        minimumpriority: "warning"    # warning 이상만
      prometheus:
        extralabels: "cluster:prod"
EOF
```

## Step 2. 경보를 메트릭으로 — 관측 통합 (11·06)

```bash
kubectl -n falco port-forward svc/falco-falcosidekick 2801:2801 >/dev/null 2>&1 &
sleep 3
curl -s http://localhost:2801/metrics 2>/dev/null | grep "falcosidekick" | head -4 || \
  echo "(Falcosidekick 메트릭 엔드포인트)"
kill %1 2>/dev/null || true

cat <<'EOF'
관측 통합 (06의 격자, 11):
  falco_events_total{rule, priority}       규칙별 발생
  falcosidekick_outputs_total{destination} 대응 전송

PromQL:
  sum by(rule)(rate(falco_events_total{priority="Warning"}[5m]))
  → 어느 규칙이 자주 울리나 (오탐 튜닝의 데이터)

★ 06의 알림 설계:
  경보를 대시보드·알람으로 → "탐지가 살아있다"의 증거
  falco_events가 0이면? 탐지가 죽었거나 규칙이 안 맞는 것 (감시의 감시)
EOF
```

## Step 3. 자동 대응 — 신중한 격리

```bash
cat <<'EOF'
=== 경보 → 자동 격리 (theory §5) ===
Response Engine / Falcosidekick + 함수:
  경보(예: 컨테이너 내 셸) → 트리거 → 액션:
    ① NetworkPolicy 주입 (그 Pod 격리 — 04)
    ② Pod 라벨 변경 (서비스에서 제외)
    ③ Pod 삭제 (재생성 — 단 공격자가 다시 옴)
    ④ 노드 격리 (심각한 경우)

★ 자동 격리의 위험:
  Falco는 '탐지'라 오탐이 있습니다 → 오탐에 자동 격리하면 정상 워크로드를 죽입니다
  → 초기엔 알림만, 신뢰 쌓인 규칙에만 자동 대응
  → 심각도별 차등: NOTICE는 알림, CRITICAL은 격리
  (예방[admission]의 자동 차단과 다릅니다 — 탐지의 자동 대응은 오탐 비용이 큽니다)
EOF
```

## Step 4. 대응 동선 — 07 시간선의 완성

```bash
cat <<'EOF'
=== 07 사고 사례가 필요했던 것 (완성) ===
07 사고: 침해 후 2주간 공격이 진행됐지만 아무도 몰랐습니다
  → 탐지도 없었고(Falco 없음), 있었어도 경보를 볼 체계가 없었습니다

완성된 대응 동선:
  1. 탐지(Falco): 컨테이너 내 셸 → 경보
  2. 팬아웃(Falcosidekick): Slack + Prometheus + 저장
  3. 트리아지: 심각도 판정 (오탐? 진짜?)
  4. 대응: 알림(온콜) → 필요시 격리 → 조사
  5. 사후: 포스트모템 → 새 규칙 (사고가 규칙이 됩니다)

★ 탐지 도구를 깔았다 ≠ 안전
  경보에 반응하는 사람·자동화가 있어야 방어 (07의 명제)
EOF
```

## Step 5. 비교 — Falco vs Tetragon vs seccomp (22와 연결)

```bash
cat <<'EOF'
=== 런타임 보안 3층 (theory §6) ===
| | 성격 | 방식 | 07 시간선 |
|---|---|---|---|
| seccomp/AppArmor | 예방 | 커널이 시스템콜 자체를 제한 | 실행 중(예방) |
| Falco | 탐지 | eBPF로 시스템콜 감시 → 경보 | 실행 중(탐지) |
| Tetragon(22) | 강제 | eBPF로 감시 + 실시간 차단 | 실행 중(탐지+강제) |

구분:
  seccomp: "이 컨테이너는 이 시스템콜들만 허용" (공격 표면 축소, 예방)
    → runtime/default 프로파일로 위험한 시스템콜 차단
  Falco: "이런 행위가 보이면 경보" (탐지, 풍부한 규칙)
  Tetragon: "이런 행위가 보이면 차단" (강제, Cilium 스택)

조합 (07의 층의 곱):
  seccomp로 공격 표면 축소(예방)
  + Falco로 이상 탐지(경보)
  + (필요시) Tetragon으로 특정 행위 차단(강제)
  → 대체가 아니라 다층
EOF
```

## Step 6. seccomp 맛보기 — 예방 층

```bash
# runtime/default seccomp 프로파일 적용 (예방)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: hardened }
spec:
  securityContext:
    seccompProfile: { type: RuntimeDefault }   # ★ 위험한 시스템콜 차단
  containers:
    - name: app
      image: nginx
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: { drop: ["ALL"] }
EOF
kubectl wait --for=condition=ready pod/hardened --timeout=60s

cat <<'EOF'
seccomp RuntimeDefault (예방):
  컨테이너 런타임(26)의 기본 프로파일 → 위험한 시스템콜(예: 일부 mount, ptrace) 차단
  → 공격 표면 축소 (Falco가 탐지할 것 자체를 줄입니다)
  ★ Falco(탐지) 앞에 seccomp(예방)를 두는 것이 다층 방어
EOF
```

## Step 7. 산출물 — 런타임 보안 종합

```markdown
# 런타임 보안 카드 (07 시간선의 실행 중 완성)
## 3층
- 예방: seccomp/AppArmor (시스템콜 제한, 공격 표면 축소)
- 탐지: Falco (이상 행위 경보, 풍부한 규칙)
- 강제: Tetragon/KubeArmor (eBPF 실시간 차단)

## Falco 운영
- 탐지 → Falcosidekick 팬아웃(알림·메트릭·저장) → 트리아지 → 대응 → 사후
- 자동 격리는 신뢰 규칙에만(탐지의 오탐 비용)
- 튜닝으로 오탐 관리(06의 알림 설계)
- falco_events 메트릭 = 탐지의 생존 증거

## 07 사고 사례의 처방
- 탐지 있어야 침해를 본다 + 경보에 반응하는 체계 필수
- "탐지 도구 = 안전"이 아닙니다 (경보→대응이 완성)
```

## 정리

```bash
bash cleanup.sh
```
