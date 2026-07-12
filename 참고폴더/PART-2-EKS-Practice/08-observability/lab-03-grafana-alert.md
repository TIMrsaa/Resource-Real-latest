# Lab 03 — Grafana 대시보드 + Alert

## 학습 확인 포인트

- [ ] 외부 대시보드를 ID로 import
- [ ] PrometheusRule CRD 로 alert 정의
- [ ] Alertmanager 에서 active alert 확인

> **🌱 핵심 개념 미리보기**
> - **Grafana Dashboard**: 패널들의 모음. JSON으로 export/import 가능. ID로 [grafana.com/dashboards](https://grafana.com/grafana/dashboards/) 의 공개 대시보드 가져오기 가능
> - **PrometheusRule (CRD)**: 알람/recording 규칙을 K8s 객체로 관리
> - **Alertmanager**: 받은 알람을 그룹화/라우팅/억제 후 외부 채널로 전송

## 1. Grafana 외부 대시보드 import

Grafana UI (http://localhost:3000) → 좌측 + 메뉴 → Import.

추천 ID들:
- **315** — Kubernetes cluster monitoring
- **1860** — Node Exporter Full
- **7249** — Kubernetes Cluster (Prometheus)
- **6417** — Kubernetes Cluster (autoscaling 시각)
- **8588** — Kubernetes Deployment Statefulset Daemonset

각 ID 입력 → Load → Datasource: `Prometheus` 선택 → Import.

대시보드들이 자동으로 데이터 표시.

> **🧠 ID로 import 가 가능한 이유**
> grafana.com에 커뮤니티가 올린 대시보드 JSON 저장소가 있음.
> Grafana가 ID 받으면 → grafana.com에서 JSON 가져옴 → "Datasource는 뭘 쓸래?" 물어봄 → import.
>
> 운영에선 외부 대시보드 그대로 쓰지 말고: 검토 후 자기 레포에 보관 → IaC로 적용 (Part-5-22의 ConfigMap 패턴).

## 2. PrometheusRule 로 alert 정의

```bash
kubectl apply -f manifests/prometheusrule.yaml
kubectl get prometheusrule -n monitoring eks-study-app-rules
```

> **🧠 PrometheusRule 구조**
> ```yaml
> spec:
>   groups:
>     - name: 그룹이름
>       interval: 30s   # 평가 주기
>       rules:
>         - alert: 알람이름        # ← 이게 alert
>           expr: PromQL 식
>           for: 5m                # 이 시간 동안 참이어야 firing
>           labels: {severity: warning}
>           annotations: {summary: "..."}
>         - record: 메트릭이름     # ← 이게 recording rule
>           expr: PromQL 식         # 결과를 새 메트릭으로 저장
> ```
>
> Operator가 이 객체를 보면 → Prometheus의 ConfigMap을 자동 갱신 → reload.
>
> **`for: 5m` 의 의미**:
> ```
>   t=0   조건 참 → Pending (firing 아님)
>   t=1m  조건 참 → Pending
>   t=3m  조건 거짓 → 카운터 리셋
>   t=4m  조건 참 → Pending (다시 0부터)
>   t=9m  조건 참 (5m 연속) → Firing! → Alertmanager 발송
> ```
> 일시적 spike 무시, 지속적 문제만 잡기 위함.

## 3. Prometheus UI 에서 rule 확인

http://localhost:9090/rules — 등록된 rule 그룹 목록.

> **`/rules` 페이지에서 봐야 할 것**:
> - 각 rule의 평가 시간 (slow 한 게 있으면 PromQL 최적화 필요)
> - 에러 (PromQL 문법 오류 시 표시됨)
> - 마지막 평가 시각

## 4. CrashLoop alert 인위적으로 발생시키기

```bash
kubectl run crashloop --image=busybox -- sh -c "exit 1"
kubectl get pod crashloop --watch    # CrashLoopBackOff 로 진입
```

> **🧠 CrashLoopBackOff 동작**
> 컨테이너가 실패 종료 → kubelet이 재시작 → 또 실패 → 재시작 간격을 점점 늘림 (10s → 20s → 40s → max 5min).
> 이게 "BackOff" 의 의미. 폭주 방지.
>
> `restartPolicy: Always` (Deployment 기본) 일 때만 발생. `Never` 면 그냥 Failed.

5분 정도 기다리기 (`for: 5m` 임계).

http://localhost:9090/alerts — `PodCrashLooping` 이 `Pending` → `Firing`.

## 5. Alertmanager UI

```bash
kubectl port-forward -n monitoring svc/kps-kube-prometheus-stack-alertmanager 9093:9093 &
```

브라우저: http://localhost:9093

활성 alert 가 보임 + 라우팅, 묵음(silence) 가능.

> **🧠 Silence (침묵) 기능**
> 점검 중일 때 알람 일시 차단. 라벨 매처로 어떤 alert를 침묵할지 지정.
> 예: "namespace=staging 의 알람을 2시간 침묵" → 점검 중 false alert 방지.
> 침묵은 만료 시간 후 자동 해제.

## 6. Alertmanager 라우팅 (Slack 예시)

(실제 Slack webhook이 있어야 동작 — 학습용 참고)

```bash
cat > /tmp/alertmanager-config.yaml <<'EOF'
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: eks-study-alerts
  namespace: monitoring
  labels:
    alertmanagerConfig: kps
spec:
  route:
    receiver: slack-warning
    groupBy: [namespace, alertname]
    routes:
      - matchers:
          - {name: severity, value: critical}
        receiver: slack-critical
  receivers:
    - name: slack-warning
      slackConfigs:
        - apiURL: <YOUR_SLACK_WEBHOOK_URL>
          channel: '#eks-warning'
          sendResolved: true
    - name: slack-critical
      slackConfigs:
        - apiURL: <YOUR_SLACK_WEBHOOK_URL>
          channel: '#eks-critical'
          sendResolved: true
EOF
```

> 실제 webhook 없으면 적용 안 함. 운영에서는 PagerDuty / Opsgenie 등.

> **🧠 라우팅 트리 동작**
> ```
>   알람 들어옴
>     ↓
>   route (top-level): receiver=slack-warning (기본)
>     ↓ 자식 routes 매칭 시도
>   severity=critical → slack-critical (매칭됨, 여기로)
>   매칭 안 되면 → 부모의 slack-warning
> ```
>
> **`groupBy: [namespace, alertname]`**: 같은 NS + 같은 alert 이름끼리 묶어 한 번에 발송.
> 폭주 방지에 핵심 (100개 Pod 동시 죽어도 1개 알람으로 통합).
>
> **`sendResolved: true`**: 알람 해소 시 "🟢 RESOLVED" 메시지 추가 발송. 운영자에게 좋음.

## 7. Alert 정리

```bash
kubectl delete pod crashloop
kubectl delete prometheusrule -n monitoring eks-study-app-rules
```

## 8. 모듈 cleanup (Container Insights + kube-prometheus-stack)

```bash
# Prometheus stack
helm uninstall kps -n monitoring
kubectl delete pvc -n monitoring -l release=kps    # PV 정리
kubectl delete ns monitoring

# CloudWatch Container Insights addon
eksctl delete addon --name amazon-cloudwatch-observability --cluster eks-study --region ap-northeast-2

# CloudWatch Logs Group 삭제 (비용 정지)
for lg in $(aws logs describe-log-groups \
  --log-group-name-prefix /aws/containerinsights/eks-study/ \
  --query 'logGroups[].logGroupName' --output text); do
  aws logs delete-log-group --log-group-name "$lg"
done

kubectl delete ns amazon-cloudwatch --ignore-not-found
```

> **⚠️ PVC 삭제 누락 주의**
> `helm uninstall` 만 하면 Prometheus의 PVC는 안 지워짐 (데이터 보호).
> 학습용으론 즉시 삭제. 운영 클러스터에선 신중히!

## 학습 확인 질문

1. PrometheusRule의 `for: 5m` 의 의미는?
2. Grafana 대시보드의 데이터는 어디서 오는가? (저장소 / 쿼리 메커니즘)
3. Alertmanager 가 Prometheus 와 분리된 이유는?

> **힌트**:
> 1. 조건이 5분간 연속 참이어야 firing. 일시 spike 무시.
> 2. Grafana는 자체 데이터 저장 X. 패널이 그릴 때마다 Prometheus(데이터소스)에 PromQL 쿼리. Grafana DB는 대시보드 정의/사용자/설정만 저장.
> 3. (a) 라우팅 로직 분리 → Prometheus 단순화. (b) 여러 Prometheus 인스턴스의 알람 통합 가능. (c) HA용 Alertmanager 클러스터 구성 가능.

다음: [quiz.md](./quiz.md)
