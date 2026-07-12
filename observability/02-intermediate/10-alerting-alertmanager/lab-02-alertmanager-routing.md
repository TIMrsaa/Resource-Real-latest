# Lab 02 — Alertmanager: 라우팅·그룹핑·억제·사일런스

> 발화(lab-01) 이후의 여정을 구축합니다 — 라우팅 트리로 심각도·팀 분기, 그룹핑으로 폭풍을 한 통으로, 억제로 원인이 증상을 덮고, 사일런스로 계획 작업을 조용히. 수신자는 웹훅 수신 Pod로 흉내 내 실제 도달을 검증합니다.

## 0. 준비 (lab-01 이어서 — PaymentHighErrorRate가 firing 중)

```bash
# 수신자 흉내: 받은 웹훅을 stdout에 찍는 서버 (도달의 물증)
kubectl create namespace receivers
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: hook-pager, namespace: receivers }
spec:
  replicas: 1
  selector: { matchLabels: { app: hook-pager } }
  template:
    metadata: { labels: { app: hook-pager } }
    spec:
      containers:
        - name: c
          image: mendhak/http-https-echo:31
          ports: [{ containerPort: 8080 }]
---
apiVersion: v1
kind: Service
metadata: { name: hook-pager, namespace: receivers }
spec: { selector: { app: hook-pager }, ports: [{ port: 8080 }] }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: hook-slack, namespace: receivers }
spec:
  replicas: 1
  selector: { matchLabels: { app: hook-slack } }
  template:
    metadata: { labels: { app: hook-slack } }
    spec:
      containers:
        - name: c
          image: mendhak/http-https-echo:31
          ports: [{ containerPort: 8080 }]
---
apiVersion: v1
kind: Service
metadata: { name: hook-slack, namespace: receivers }
spec: { selector: { app: hook-slack }, ports: [{ port: 8080 }] }
EOF
```

## 1. 라우팅 트리 설정

kube-prometheus-stack의 Alertmanager 설정을 교체합니다:

```bash
cat > /tmp/am-values.yaml <<'EOF'
alertmanager:
  config:
    route:
      receiver: slack-default
      group_by: [alertname, job]
      group_wait: 15s
      group_interval: 1m
      repeat_interval: 2h
      routes:
        - matchers: [severity = "page"]
          receiver: pager                # 깨울 일 → 페이저
        - matchers: [team = "commerce"]
          receiver: slack-default        # 팀 채널
    inhibit_rules:
      - source_matchers: [alertname = "PaymentTargetMissing"]
        target_matchers: [alertname = "PaymentHighErrorRate"]
        equal: [job]                     # 타깃 소실이 울리면 에러율 알림은 침묵
    receivers:
      - name: pager
        webhook_configs:
          - url: http://hook-pager.receivers.svc:8080/
      - name: slack-default
        webhook_configs:
          - url: http://hook-slack.receivers.svc:8080/
EOF
helm upgrade monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --reuse-values -f /tmp/am-values.yaml
kubectl -n monitoring rollout status statefulset/alertmanager-monitoring-kube-prometheus-alertmanager --timeout=180s
```

## 2. 라우팅 검증 — severity=page가 페이저로

```bash
sleep 120   # firing 알림이 새 설정으로 라우팅되길 대기

kubectl -n receivers logs deploy/hook-pager | grep -o '"alertname":"[^"]*"' | tail -3
# "alertname":"PaymentHighErrorRate"   ← page 심각도가 페이저 수신자로!

kubectl -n receivers logs deploy/hook-pager | grep -o '"dashboard":"[^"]*"' | tail -1
# 대시보드 링크가 페이로드에 — 09의 착지가 알림에 실려 감 (동선의 계약)
```

**확인** — severity=page 매처가 첫 분기에서 잡아 pager 수신자로 보냈습니다. 알림 페이로드에 annotations(대시보드·runbook)가 그대로 실립니다 — 수신 도구(PagerDuty·Slack)에서 온콜이 클릭할 그 링큽니다.

## 3. 그룹핑 — 폭풍을 한 통으로

```bash
# 알림 폭풍 흉내: 여러 Pod가 걸리는 알림 추가 (재시작 반복)
cat <<'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: crash-alerts
  namespace: shop
  labels: { release: monitoring }
spec:
  groups:
    - name: crash.alerts
      rules:
        - alert: PodRestarting
          expr: increase(kube_pod_container_status_restarts_total{namespace="shop"}[10m]) > 1
          labels: { severity: page, team: commerce }
          annotations: { summary: "{{ $labels.pod }} 재시작 반복" }
EOF

# CrashLoop Pod 5개 생성 (동시 발화 유발)
for i in 1 2 3 4 5; do
  kubectl -n shop run crasher-$i --image=busybox --restart=Always -- sh -c 'exit 1' 2>/dev/null || \
  kubectl -n shop apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata: { name: crasher-$i, namespace: shop }
spec:
  restartPolicy: Always
  containers: [{ name: c, image: busybox, command: ["sh","-c","exit 1"] }]
EOF
done
sleep 600   # 재시작 누적 + 발화 대기 (10분 창)

# 페이저 수신 확인: 알림 5개가 아니라 "묶음"으로
kubectl -n receivers logs deploy/hook-pager --since=5m | grep -c '"alertname":"PodRestarting"'
# 웹훅 호출 수를 보라 — group_by: [alertname, job]이라 한 통에 alerts 배열로 5개
kubectl -n receivers logs deploy/hook-pager --since=5m | grep -o '"status":"firing"' | wc -l
```

**해부** — 페이로드를 열면 `alerts: [crasher-1, ..., crasher-5]`가 **한 웹훅 호출**에 담겨 있습니다. group_wait(15s) 동안 모아 묶음을 만들었기 때문 — 노드 하나가 죽어 Pod 50개 알림이 발화해도 전화는 한 통이라는 보호 장치입니다.

## 4. 억제 — 원인이 증상을 덮습니다

```bash
# 타깃 소실(원인)을 일으키면 에러율 알림(증상)이 억제되는지
kubectl -n shop label servicemonitor payment release-
sleep 400   # PaymentTargetMissing firing 대기 (absent + for 5m)

# Alertmanager API로 억제 상태 확인
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093 &
sleep 2
curl -s localhost:9093/api/v2/alerts | grep -o '"alertname":"[^"]*"\|"state":"[a-z]*"' | paste - - | sort | uniq
# PaymentTargetMissing → active (통지됨)
# PaymentHighErrorRate → suppressed ← ★ 억제! (같은 job이므로)
kill %1
kubectl -n shop label servicemonitor payment release=monitoring   # 복구
```

**의미** — 타깃이 사라졌다는 근본 신호가 울리는 동안, 그로 인한(또는 무의미해진) 에러율 알림은 침묵합니다. 억제 설계의 관례: 상위/원인 알림(노드 다운·타깃 소실)이 하위/증상 알림을 equal 라벨(같은 node·job)로 덮습니다 — 장애의 순간 온콜이 원인 하나에 집중하게.

## 5. 사일런스 — 계획 작업의 예의

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-alertmanager 9093:9093 &
sleep 2
# "내일 새벽 payment 마이그레이션" — 2시간짜리 사일런스 (기한 필수!)
curl -s -X POST localhost:9093/api/v2/silences -H "Content-Type: application/json" -d '{
  "matchers": [{ "name": "job", "value": "payment", "isRegex": false }],
  "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
  "endsAt": "'$(date -u -d "+2 hours" +%Y-%m-%dT%H:%M:%SZ)'",
  "createdBy": "you@example.com",
  "comment": "payment DB migration — ticket OPS-1234"
}'
curl -s localhost:9093/api/v2/silences | grep -o '"comment":"[^"]*"'
# 기한·작성자·사유가 남습니다 — "누가 왜 껐는지"의 기록
kill %1
```

**규율** — endsAt 없는(또는 아주 긴) 사일런스는 알림 삭제와 같습니다 — 만료를 짧게, 사유·티켓을 남기고, 작업이 끝나면 조기 해제. 주기적으로 활성 사일런스 목록을 리뷰하세요(몰래 썩는 지점).

## 6. 정리

```bash
kind delete cluster --name alerts
rm -f /tmp/am-values.yaml
```

## 정리

- 라우팅: severity 1차(page→페이저)·team 2차 — 페이로드에 대시보드·runbook 동승
- 그룹핑: group_by+group_wait — Pod 5개 발화가 웹훅 1통 (폭풍 보호)
- 억제: 원인(타깃 소실)이 증상(에러율)을 equal 라벨로 덮음 — suppressed 상태 확인
- 사일런스: 기한·작성자·사유 필수 — 영구 사일런스는 알림 삭제와 같습니다
- **★ 발화의 규율(lab-01) × 전달의 설계(lab-02) = "맞는 알림만, 맞는 사람에게, 한 번만"**
