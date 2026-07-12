# Lab 01 — 신호의 원산지 투어

> 수집기를 하나도 깔지 않은 맨 클러스터에서, 신호 4종이 **이미 태어나 있는 곳**을 kubectl과 노드 셸로 직접 확인합니다. 이 투어가 끝나면 "Fluent Bit·Prometheus가 무엇을 어디서 가져오는지"가 당연해집니다.

## 0. 준비

```bash
kind create cluster --name obs-tour
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels: { app: web }
spec:
  replicas: 2
  selector:
    matchLabels: { app: web }
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
        - name: nginx
          image: nginx
EOF
kubectl wait deploy/web --for=condition=Available --timeout=120s
```

## 1. 로그의 원산지 — stdout이 파일이 되는 곳

```bash
# 앱이 stdout에 쓰면 kubectl logs로 보입니다 — 그 사이에 무엇이 있나요?
kubectl logs deploy/web --tail=3

# 노드(kind 컨테이너) 안으로 들어가 실제 파일을 봅니다
docker exec -it obs-tour-control-plane bash

ls /var/log/pods/
# default_web-xxxxx_<uid>/  ← Pod마다 디렉터리!
ls /var/log/pods/default_web-*/web/
# 0.log   ← containerd가 stdout을 받아 쓰는 실제 파일

tail -2 /var/log/pods/default_web-*/web/0.log
# 2026-07-11T12:00:00.000Z stdout F 10.244.0.1 - - [11/Jul/2026...] "GET / HTTP/1.1" 200
#   ↑시각                    ↑스트림 ↑플래그  ↑앱이 쓴 원문
exit
```

**핵심** — `kubectl logs`는 마법이 아닙니다: 앱 stdout → containerd가 노드 파일(`/var/log/pods/...`)에 기록 → kubelet이 그 파일을 읽어 API로 제공. **Fluent Bit(06)가 하는 일도 같은 파일을 읽는 것**입니다(DaemonSet으로 노드마다 앉아서). 로그의 원산지 = 노드의 이 디렉터리.

## 2. 메트릭의 원산지 ① — kubelet의 cAdvisor

```bash
# kubelet이 이미 컨테이너 리소스 메트릭을 노출하고 있습니다 (cAdvisor 내장)
kubectl get --raw /api/v1/nodes/obs-tour-control-plane/proxy/metrics/cadvisor | head -30
# HELP container_cpu_usage_seconds_total ...
# TYPE container_cpu_usage_seconds_total counter
# container_cpu_usage_seconds_total{container="web",namespace="default",pod="web-..."} 0.24
```

**관찰** — Prometheus를 깔지 않았는데 메트릭이 이미 있습니다. `container_cpu_usage_seconds_total{...}` — 이름+라벨+값의 Prometheus 노출 형식(03에서 심층)입니다. **Prometheus(08)가 하는 일은 이 엔드포인트를 주기적으로 긁는 것**(pull)입니다. `kubectl top`이 안 되는 것도 확인:

```bash
kubectl top pod
# error: Metrics API not available   ← metrics-server가 없어서 (03에서 설치)
# 원천(cAdvisor)은 있지만 그것을 Metrics API로 제공하는 컴포넌트가 없습니다
```

## 3. 메트릭의 원산지 ② — API 서버 자신

```bash
# 컨트롤 플레인 컴포넌트도 자기 메트릭을 노출합니다
kubectl get --raw /metrics | grep -E "^apiserver_request_total" | head -5
# apiserver_request_total{code="200",resource="pods",verb="LIST",...} 42
# → API 서버가 받은 요청의 수·코드·리소스별 카운터
```

**관찰** — 클러스터의 심장(API 서버·etcd·스케줄러)도 전부 `/metrics`를 노출합니다. "K8s를 관측한다"의 절반은 이 내장 메트릭들을 수집하는 것입니다.

## 4. 이벤트의 원산지 — API 서버의 Events

```bash
# 방금 Deployment를 만들 때 생긴 사건들
kubectl get events --sort-by=.lastTimestamp | tail -8
# ... Scheduled  Successfully assigned default/web-... to obs-tour-control-plane
# ... Pulling    Pulling image "nginx"
# ... Started    Started container web

# 사건을 일부러 만들어 봅니다: 이미지 오타
kubectl run broken --image=nginx:doesnotexist
sleep 10
kubectl get events --field-selector involvedObject.name=broken | tail -3
# ... Failed     Failed to pull image "nginx:doesnotexist"
# ... BackOff    Back-off pulling image
```

```bash
# ★ Events의 함정: 기본 보존이 짧습니다 (기본 1시간)
kubectl get event -o jsonpath='{.items[0].metadata.creationTimestamp}'
# → 1시간 뒤 이 이벤트는 사라집니다. "어젯밤 무슨 일이?"에 답하려면
#   Events를 로그처럼 수집해 보존해야 (05에서 다룸)
```

## 5. 트레이스의 원산지 — 아직 없습니다 (그게 포인트)

```bash
# 로그·메트릭·이벤트는 플랫폼이 공짜로 주지만...
# 트레이스는? nginx Pod 어디에도 없습니다.
kubectl exec deploy/web -- ls /tmp 2>/dev/null   # 아무 트레이스도 없음
```

**핵심** — 트레이스만은 **앱이 계측(SDK)되어야 태어납니다**(04·11). 플랫폼이 자동으로 주는 신호(로그·메트릭·이벤트)와 앱이 만들어야 하는 신호(트레이스)의 차이 — 이것이 "트레이스 도입이 항상 늦어지는" 구조적 이유이고, eBPF 관측(19)이 "계측 없이"를 시도하는 배경입니다.

## 6. 원산지 지도 정리 (직접 그려보기)

투어 결과를 표로 정리하세요:

| 신호 | 원산지 | 이미 있나요? | 수집기가 할 일 |
|------|--------|-----------|---------------|
| 로그 | 노드 `/var/log/pods/` | ✅ (containerd가 씀) | 파일 tail → 전송 (06) |
| 컨테이너 메트릭 | kubelet cAdvisor | ✅ | 주기적 scrape (08) |
| 플랫폼 메트릭 | 각 컴포넌트 `/metrics` | ✅ | 〃 |
| 앱 메트릭 | 앱 `/metrics` | 앱이 노출해야 | 〃 (03) |
| 이벤트 | API 서버 (1h 휘발) | ✅ 단 휘발 | 수집해 보존 (05) |
| 트레이스 | 앱 SDK | ❌ 계측 필요 | 받아서 전송 (11) |

## 7. 정리

```bash
kubectl delete deploy web
kubectl delete pod broken
# 클러스터는 lab-02에서 계속 사용
```

## 정리

- `kubectl logs`의 실체: stdout → containerd 파일(`/var/log/pods/`) → kubelet — **Fluent Bit도 같은 파일을 읽습니다**
- 메트릭은 이미 도처에: cAdvisor(컨테이너), API 서버·etcd(플랫폼) — **Prometheus는 긁을 뿐**
- Events는 풍부하지만 **기본 1시간 휘발** — 보존하려면 수집 필요
- 트레이스만 앱 계측이 필요 — 자동으로 태어나지 않는 유일한 신호
- **★ 수집기를 깔기 전에 원산지를 알라 — 파이프라인 설계는 "어디서→어디로"의 문제입니다**
