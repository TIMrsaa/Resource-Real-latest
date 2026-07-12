# Lab 02 — 버퍼·백프레셔: 유실을 재현하고 방어합니다

> 목적지를 일부러 죽이고 살리며 세 가지 유실 시나리오(목적지 다운·재시작·재시도 초과)를 재현하고, filesystem 버퍼·DB·Retry_Limit·드롭 메트릭으로 방어를 구축합니다. cncf 14의 물리가 설정으로 번역되는 현장입니다.

## 0. 준비 (lab-01 클러스터 이어서) — 죽일 수 있는 목적지

```bash
# HTTP 목적지 (Fluent Bit http output → 이 서버) — 켰다 껐다 할 대상
kubectl create namespace sink
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: log-sink, namespace: sink }
spec:
  replicas: 1
  selector: { matchLabels: { app: log-sink } }
  template:
    metadata: { labels: { app: log-sink } }
    spec:
      containers:
        - name: sink
          image: hashicorp/http-echo
          args: ["-listen=:8080", "-text=ok"]
---
apiVersion: v1
kind: Service
metadata: { name: log-sink, namespace: sink }
spec:
  selector: { app: log-sink }
  ports: [{ port: 8080 }]
EOF

# 로그 발생기 재가동
kubectl create namespace shop 2>/dev/null || true
kubectl -n shop create deployment talker --image=busybox -- \
  sh -c 'i=0; while true; do i=$((i+1)); echo "{\"seq\":$i,\"msg\":\"hello\"}"; sleep 0.05; done'
```

## 1. 시나리오 A — mem 버퍼 + 목적지 다운 = 조용한 유실

```yaml
# /tmp/fb-values.yaml의 outputs를 http로 교체 (mem 버퍼, 기본)
  outputs: |
    [OUTPUT]
        Name              http
        Match             kube.*
        Host              log-sink.sink.svc.cluster.local
        Port              8080
        URI               /
        Format            json
        Retry_Limit       2
```

```bash
helm upgrade fluent-bit fluent/fluent-bit -n monitoring -f /tmp/fb-values.yaml
kubectl -n monitoring rollout status ds/fluent-bit --timeout=120s
sleep 10

# 정상 흐름 확인 (재시도 0)
kubectl -n monitoring port-forward ds/fluent-bit 2020:2020 &
sleep 2
curl -s localhost:2020/api/v1/metrics/prometheus | grep -E "retries_total|dropped" 
# fluentbit_output_retries_total{name="http.0"} 0

# ★ 목적지 사망
kubectl -n sink scale deploy/log-sink --replicas=0
sleep 60

curl -s localhost:2020/api/v1/metrics/prometheus | grep -E "retries_total|retries_failed|dropped_records"
# fluentbit_output_retries_total{...} 14          ← 재시도 몸부림
# fluentbit_output_retries_failed_total{...} 5    ← Retry_Limit(2) 초과
# fluentbit_output_dropped_records_total{...} 3200 ← ★ 유실! (조용히)
kill %1
```

**관찰** — 목적지가 죽자 재시도(2회)를 소진한 chunk들이 **드롭**됐습니다. 이 순간 아무 경보도 없었습니다 — 메트릭을 안 보면 **유실은 조용합니다**. seq 로그라 나중에 목적지에서 번호 구멍으로도 확인 가능(유실의 물증). 이것이 "기본 설정 + 장애 = 조용한 유실"의 현실입니다.

## 2. 시나리오 B — filesystem 버퍼로 방어

```yaml
# service에 storage 설정, input·output에 storage 적용
  service: |
    [SERVICE]
        Flush         1
        Log_Level     info
        HTTP_Server   On
        HTTP_Listen   0.0.0.0
        HTTP_Port     2020
        storage.path              /var/log/flb-storage/
        storage.sync              normal
        storage.max_chunks_up     128
        storage.metrics           On
  inputs: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/*.log
        Tag               kube.*
        multiline.parser  cri
        DB                /var/log/flb_kube.db
        Mem_Buf_Limit     20MB
        storage.type      filesystem          # ★ 이 input은 fs 버퍼
  outputs: |
    [OUTPUT]
        Name              http
        Match             kube.*
        Host              log-sink.sink.svc.cluster.local
        Port              8080
        URI               /
        Format            json
        Retry_Limit       False                # ★ 무제한 재시도 (fs가 받쳐주니)
        storage.total_limit_size  500M         # 단, 디스크 한도는 설정
```

```bash
helm upgrade fluent-bit fluent/fluent-bit -n monitoring -f /tmp/fb-values.yaml
kubectl -n monitoring rollout status ds/fluent-bit --timeout=120s

# 다시 목적지 사망 → 이번엔 fs 버퍼에 쌓입니다
kubectl -n sink scale deploy/log-sink --replicas=0
sleep 60

kubectl -n monitoring port-forward ds/fluent-bit 2020:2020 &
sleep 2
curl -s localhost:2020/api/v1/metrics/prometheus | grep -E "fs_chunks|dropped_records"
# fluentbit_output_dropped_records_total{...} 0     ← ★ 드롭 없음!
# storage 메트릭: fs chunk 수가 증가 중 (적체가 "보임")
kill %1

# 목적지 부활 → 밀린 로그 배달
kubectl -n sink scale deploy/log-sink --replicas=1
sleep 60
kubectl -n monitoring port-forward ds/fluent-bit 2020:2020 &
sleep 2
curl -s localhost:2020/api/v1/metrics/prometheus | grep "proc_records_total"
# 출력 카운트가 크게 점프 — 밀렸던 chunk들이 배달됨 (유실 0)
kill %1
```

**관찰** — 같은 장애에서 이번엔 **드롭 0**. fs 버퍼가 목적지 다운을 흡수했고, 부활하자 밀린 것을 배달했습니다. 대가: 노드 디스크 사용(한도 500M 설정 — 무한이면 디스크가 새 피해자). **mem(빠름·휘발) vs fs(느림·생존)**의 트레이드오프에서 프로덕션은 fs가 표준입니다.

## 3. 시나리오 C — 재시작 생존 (DB + fs)

```bash
# 목적지를 죽인 채 버퍼를 쌓고 → Fluent Bit 재시작
kubectl -n sink scale deploy/log-sink --replicas=0
sleep 30
kubectl -n monitoring rollout restart ds/fluent-bit
kubectl -n monitoring rollout status ds/fluent-bit --timeout=120s

# 재시작 후에도: fs chunk가 hostPath에 남아 재적재 + tail DB로 이어 읽기
kubectl -n sink scale deploy/log-sink --replicas=1
sleep 60
# 목적지 로그(양)나 메트릭으로 밀린 분이 배달됐는지 확인
kubectl -n monitoring logs ds/fluent-bit | grep -i "storage" | head -3
# ... [storage] ... chunks up ... ← 재시작 시 fs에서 chunk 복구 로그
```

**핵심** — fs 버퍼(hostPath)와 tail DB 덕에 재시작이 유실로 이어지지 않았습니다. mem 버퍼였다면 재시작 순간 미전송분이 증발했을 것. **업그레이드·재배포가 일상인 K8s에서 fs 버퍼는 선택이 아닙니다.**

## 4. 방어 체크리스트 (설정 → 시나리오 대응표)

```
시나리오                    방어 설정
목적지 다운(일시)      →    storage.type filesystem + total_limit_size
목적지 다운(장기)      →    한도 도달 시 정책 인지 + ★ 드롭 메트릭 알림
Fluent Bit 재시작     →    fs 버퍼 + tail DB (hostPath 영속)
영구 실패(4xx)        →    Retry_Limit 유한 + retries_failed 알림
로그 폭주             →    Mem_Buf_Limit·필터 + (02) 앱 측 rate-limit
tail이 로테이션에 짐   →    수집기 리소스 확보 + 폭주 앱 통제 (02 사고)

원칙: 유실 0은 불가능한 목표 — "유실이 보이고(메트릭), 견딜 만큼
      버티고(fs 버퍼), 정책적으로 포기(한도·Retry_Limit)"가 설계입니다
```

## 5. 정리

```bash
kind delete cluster --name fluentbit
rm -f /tmp/fb-values.yaml
```

## 정리

- mem 버퍼 + 장애 = **조용한 유실** (dropped 메트릭만이 증인 — 알림 필수)
- fs 버퍼: 목적지 다운을 흡수하고 재시작에도 생존 — 프로덕션 표준 (대가: 노드 디스크, 한도 필수)
- tail DB로 오프셋 영속 — 재시작 시 이어 읽기
- Retry_Limit: 무한(fs가 받칠 때) vs 유한(영구 실패 대응) — 상황별 정책
- **★ 유실 0이 아니라 "보이는 유실, 버티는 버퍼, 의도된 포기"가 수집기 설계입니다 (cncf 14의 물리 → 설정)**
