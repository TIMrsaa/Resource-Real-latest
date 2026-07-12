# Lab 01 — Events 해부·수집과 audit 로그 활성화

> Events의 단골 reason들을 일부러 만들어 사전을 몸으로 익히고, Events를 로그로 변환(수집)해 휘발을 이기고, kind에서 audit 로그를 켜 "누가?"에 답해 봅니다.

## 0. 준비 — audit을 켠 클러스터

audit은 API 서버 플래그가 필요해 클러스터 생성 시 설정합니다:

```bash
mkdir -p /tmp/audit
# 최소 audit 정책: 시크릿은 Metadata, 삭제는 상세, 나머지 최소
cat > /tmp/audit/policy.yaml <<'EOF'
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
    resources: [{ group: "", resources: ["secrets"] }]
  - level: Request
    verbs: ["delete", "create", "patch", "update"]
  - level: None                # 나머지 (읽기 대량)는 기록 안 함
EOF

cat > /tmp/audit/kind.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: ClusterConfiguration
        apiServer:
          extraArgs:
            audit-policy-file: /etc/kubernetes/audit/policy.yaml
            audit-log-path: /var/log/kubernetes/audit.log
          extraVolumes:
            - name: audit
              hostPath: /etc/kubernetes/audit
              mountPath: /etc/kubernetes/audit
              readOnly: true
            - name: audit-log
              hostPath: /var/log/kubernetes
              mountPath: /var/log/kubernetes
    extraMounts:
      - hostPath: /tmp/audit
        containerPath: /etc/kubernetes/audit
EOF
kind create cluster --name signals --config /tmp/audit/kind.yaml
```

## 1. Events 사전 만들기 — 단골 사건들을 일부러

```bash
# ① ImagePullBackOff
kubectl run bad-image --image=nginx:no-such-tag

# ② FailedScheduling (불가능한 리소스 요구)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: too-big
  labels: { run: too-big }
spec:
  containers:
    - name: too-big
      image: nginx
      resources:
        requests: { cpu: "64" }
EOF

# ③ OOMKilled (한도보다 많이 쓰기)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: oomer }
spec:
  containers:
    - name: c
      image: busybox
      command: ["sh","-c","head -c 200m /dev/zero | tail; sleep 3600"]
      resources: { limits: { memory: "64Mi" } }
EOF

# ④ Unhealthy (실패하는 프로브)
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata: { name: unhealthy }
spec:
  containers:
    - name: c
      image: nginx
      livenessProbe:
        httpGet: { path: /nope, port: 9999 }
        periodSeconds: 3
EOF
sleep 45
```

```bash
# 사건 수확 — Warning만 모아 읽기
kubectl get events --field-selector type=Warning --sort-by=.lastTimestamp \
  -o custom-columns=OBJ:.involvedObject.name,REASON:.reason,MSG:.message | tail -12
# bad-image    Failed            Failed to pull image "nginx:no-such-tag"...
# bad-image    BackOff           Back-off pulling image
# too-big      FailedScheduling  0/1 nodes are available: 1 Insufficient cpu
# oomer        BackOff           Back-off restarting failed container
# unhealthy    Unhealthy         Liveness probe failed: ...connection refused
```

```bash
# OOMKilled은 이벤트+상태 양쪽에서
kubectl get pod oomer -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'
# OOMKilled   ← describe·상태에 남습니다 (02의 --previous와 함께 재시작 조사 세트)
```

**정리** — 방금 만든 표가 theory 1절의 사전입니다. 각 reason이 "무엇을 확인하라"로 직결됩니다: FailedScheduling→리소스·taint, ImagePull→태그·인증, OOMKilled→limits·메모리 프로파일(20), Unhealthy→프로브 설정·앱 상태.

## 2. Events 휘발 이기기 — 로그로 변환(수집)

```bash
# kubernetes-event-exporter: Events를 watch해 stdout(JSON)으로
# → 02에서 배운 대로 stdout은 로그 파이프라인에 합류합니다
kubectl create namespace monitoring
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata: { name: event-exporter-cfg, namespace: monitoring }
data:
  config.yaml: |
    logLevel: error
    route:
      routes:
        - match: [{ receiver: "dump" }]
    receivers:
      - name: "dump"
        stdout: {}
---
apiVersion: v1
kind: ServiceAccount
metadata: { name: event-exporter, namespace: monitoring }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: event-exporter }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: view }
subjects: [{ kind: ServiceAccount, name: event-exporter, namespace: monitoring }]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: event-exporter, namespace: monitoring }
spec:
  replicas: 1
  selector: { matchLabels: { app: event-exporter } }
  template:
    metadata: { labels: { app: event-exporter } }
    spec:
      serviceAccountName: event-exporter
      containers:
        - name: exporter
          image: ghcr.io/resmoio/kubernetes-event-exporter:latest
          args: ["-conf=/data/config.yaml"]
          volumeMounts: [{ name: cfg, mountPath: /data }]
      volumes: [{ name: cfg, configMap: { name: event-exporter-cfg } }]
EOF
kubectl -n monitoring rollout status deploy/event-exporter --timeout=120s

# 새 사건을 만들고 exporter의 stdout에서 확인
kubectl run bad2 --image=nginx:another-bad-tag
sleep 15
kubectl -n monitoring logs deploy/event-exporter | tail -2
# {"metadata":{...},"reason":"Failed","message":"Failed to pull image \"nginx:another-bad-tag\"...","type":"Warning",...}
```

**핵심** — Events가 이제 **구조화 로그(JSON stdout)**가 됐습니다. 06의 Fluent Bit이 이 stdout을 다른 로그처럼 수집해 중앙 저장하면: 1시간 휘발 극복 + 검색("지난달 OOMKilled 전부") + 알림("Evicted 발생 시") 이 가능해집니다. **신호의 전환**(Events→로그)이 파이프라인 설계의 한 수입니다.

## 3. audit 로그 — "누가?"에 답하기

```bash
# 행위를 만듭니다: 시크릿 읽기 + Deployment 삭제
kubectl create secret generic db-pass --from-literal=p=hunter2
kubectl get secret db-pass -o yaml >/dev/null
kubectl create deployment victim --image=nginx
kubectl delete deployment victim

# audit 로그에서 추적 (노드 안 파일)
docker exec signals-control-plane sh -c \
  'grep -h "db-pass" /var/log/kubernetes/audit.log | tail -1' | head -c 400
# {"kind":"Event","level":"Metadata","verb":"get",
#  "user":{"username":"kubernetes-admin",...},
#  "objectRef":{"resource":"secrets","name":"db-pass",...},
#  "requestReceivedTimestamp":"2026-07-11T..."}
#  → ★ 누가(kubernetes-admin) 언제 어느 시크릿을 읽었나!

docker exec signals-control-plane sh -c \
  'grep -h "\"verb\":\"delete\"" /var/log/kubernetes/audit.log | grep victim | tail -1' | head -c 300
# {"level":"Request","verb":"delete","user":{"username":"kubernetes-admin"...},
#  "objectRef":{"resource":"deployments","name":"victim"...}}
#  → "누가 지웠나"의 답
```

```bash
# 정책의 효과 확인: 일반 Pod 목록 조회(get/list)는 기록됐나요?
docker exec signals-control-plane sh -c \
  'grep -c "\"resource\":\"pods\",\"" /var/log/kubernetes/audit.log' || true
# 낮은 수 — level: None 정책 덕에 대량 읽기가 안 쌓임 (비용 통제!)
```

**핵심** — 정책이 곧 비용입니다: 시크릿·변경만 기록하니 로그가 통제됩니다. 전부 RequestResponse로 켰다면 헬스체크·list가 폭주했을 것 — audit 설계는 "누가?"에 답할 최소 집합을 고르는 일입니다. EKS에서는 이 파일이 CloudWatch Logs로 갑니다(13).

## 4. 정리

```bash
kubectl delete pod bad-image too-big oomer unhealthy bad2 --force --grace-period=0 2>/dev/null || true
kubectl delete secret db-pass
# 클러스터·exporter는 lab-02에서 계속
```

## 정리

- 단골 reason 사전을 몸으로: FailedScheduling·ImagePullBackOff·OOMKilled·Unhealthy — 각각이 "무엇을 확인하라"로 직결
- Events는 exporter로 **구조화 로그로 전환** → 휘발 극복 + 검색·알림 (파이프라인 합류)
- audit로 "누가"에 답함 — 시크릿 읽기·삭제의 행위자를 특정
- audit 정책 = 비용 설계 — 상세는 민감 행위만, 대량 읽기는 None
- **★ Events와 audit는 플랫폼·사람의 행동 기록 — 앱 로그만으로는 영원히 미스터리인 질문들의 답**
