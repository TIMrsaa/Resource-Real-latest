# Lab 01 — 파이프라인 기초: 배포, CRI 파싱, 메타데이터, 라우팅

> Fluent Bit을 DaemonSet으로 배포하고, CRI 파싱→JSON 승격→k8s 메타데이터→필터링→라우팅의 전 구간을 단계별로 확인합니다. 목적지는 일단 stdout(디버그 출력)으로 — 파이프라인 자체에 집중하고, 실제 목적지는 12·13·18에서 갑니다.

## 0. 준비

```bash
kind create cluster --name fluentbit

# 테스트용 로그 발생 앱 (02 lab-02의 JSON 앱 재사용)
kubectl create namespace shop
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment
  namespace: shop
  labels: { app: payment }
spec:
  replicas: 2
  selector: { matchLabels: { app: payment } }
  template:
    metadata: { labels: { app: payment, team: commerce } }
    spec:
      containers:
        - name: app
          image: busybox
          command: ["sh","-c"]
          args:
            - |
              while true; do
                if [ $((RANDOM % 5)) -eq 0 ]; then
                  echo "{\"level\":\"error\",\"event\":\"payment_failed\",\"user_id\":$((RANDOM%100)),\"reason\":\"timeout\"}";
                else
                  echo "{\"level\":\"info\",\"event\":\"payment_ok\",\"user_id\":$((RANDOM%100))}";
                fi;
                echo "GET /healthz 200";   # 소음 (비JSON, 걸러낼 대상)
                sleep 1;
              done
EOF
```

## 1. Fluent Bit 배포 (helm) — 최소 설정에서 시작

```bash
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

cat > /tmp/fb-values.yaml <<'EOF'
config:
  service: |
    [SERVICE]
        Flush         1
        Log_Level     info
        HTTP_Server   On
        HTTP_Listen   0.0.0.0
        HTTP_Port     2020
  inputs: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/*.log
        Tag               kube.*
        multiline.parser  cri
        DB                /var/log/flb_kube.db
        Mem_Buf_Limit     20MB
  filters: |
    [FILTER]
        Name              kubernetes
        Match             kube.*
        Merge_Log         On
        Keep_Log          Off
        Use_Kubelet       Off
  outputs: |
    [OUTPUT]
        Name              stdout
        Match             kube.*
        Format            json_lines
EOF

helm install fluent-bit fluent/fluent-bit -n monitoring --create-namespace \
  -f /tmp/fb-values.yaml
kubectl -n monitoring rollout status ds/fluent-bit --timeout=120s
```

## 2. 파이프라인 출력 검증 — 세 층이 다 됐나

```bash
sleep 10
# Fluent Bit 자신의 stdout에서 payment 로그를 찾습니다
kubectl -n monitoring logs ds/fluent-bit | grep payment_failed | tail -1 | head -c 800
```

출력(정리하면):

```json
{
  "date": 1783075200.123,
  "level": "error",              ← ★ 층2: 앱 JSON이 필드로 승격 (Merge_Log)
  "event": "payment_failed",
  "user_id": 42,
  "reason": "timeout",
  "kubernetes": {                ← ★ 층3: k8s 메타데이터 부착
    "pod_name": "payment-xxx",
    "namespace_name": "shop",
    "labels": { "app": "payment", "team": "commerce" },
    "container_name": "app", "host": "fluentbit-control-plane"
  }
}
```

**검증 포인트** — ① CRI 접두어(시각/stdout/F)가 사라짐(층1: cri 파서), ② `level`·`event`가 최상위 필드(층2: Merge_Log — 02의 구조화가 여기서 보상), ③ 네임스페이스·라벨 부착(층3: kubernetes 필터 — "어느 앱 로그인가"가 데이터가 됨). 비JSON 줄(`GET /healthz 200`)은 `log` 필드에 통째로 들어있는 것도 확인하세요 — 구조화 안 된 로그의 모습입니다.

## 3. 필터링 — 소음을 소스에서 자르기 (비용의 첫 수문)

```bash
# healthz 줄을 걸러낸다 + debug 이하 제외 예시
cat >> /tmp/fb-values.yaml <<'EOF'
EOF
# filters 섹션을 교체 (grep 필터 추가)
sed -i 's/  filters: |/  filters: |\n    [FILTER]\n        Name    grep\n        Match   kube.*\n        Exclude log \\/healthz/' /tmp/fb-values.yaml 2>/dev/null || true
```

sed가 번거로우니 values를 직접 수정하는 게 명확합니다 — filters 섹션을 다음으로 교체:

```yaml
  filters: |
    [FILTER]
        Name              kubernetes
        Match             kube.*
        Merge_Log         On
        Keep_Log          Off
        Use_Kubelet       Off
    [FILTER]
        Name              grep
        Match             kube.*
        Exclude           log /healthz
```

```bash
helm upgrade fluent-bit fluent/fluent-bit -n monitoring -f /tmp/fb-values.yaml
kubectl -n monitoring rollout status ds/fluent-bit --timeout=120s
sleep 10

kubectl -n monitoring logs ds/fluent-bit --since=10s | grep -c healthz || echo "0"
# 0   ← healthz가 파이프라인에서 사라짐!
kubectl -n monitoring logs ds/fluent-bit --since=10s | grep -c payment_ok
# 여전히 흐름 (필요한 것은 통과)
```

**의미** — 초당 1건×Pod 2개×86400초 = 하루 17만 건의 무의미한 healthz가 **전송·저장·인덱싱 전 단계에서** 사라졌습니다. 대규모라면 이 필터 한 줄이 월 수백만 원입니다(22). 거를 것: 헬스체크·debug(프로덕션)·알려진 소음. 남길 것: 판단이 서지 않으면 남깁니다(지나친 필터링으로 조사 불능이 되는 것이 더 비쌉니다 — 균형).

## 4. tag 라우팅 — 네임스페이스별 다른 목적지 (개념 실습)

```yaml
# outputs를 교체: shop 네임스페이스는 "중요" 경로, 나머지는 "일반" 경로
  outputs: |
    [OUTPUT]
        Name              stdout
        Match             kube.*shop*        # ★ tag에 경로가 있어 ns로 매칭 가능
        Format            json_lines
    [OUTPUT]
        Name              null               # 나머지는 버리는 시늉 (개념용)
        Match             kube.*
```

```bash
helm upgrade fluent-bit fluent/fluent-bit -n monitoring -f /tmp/fb-values.yaml
kubectl -n monitoring rollout status ds/fluent-bit --timeout=120s
sleep 10
kubectl -n monitoring logs ds/fluent-bit --since=10s | grep -v shop | grep -c kube_system 2>/dev/null || echo "kube-system 로그는 stdout에 안 옴 (null로 감)"
```

**핵심** — tag(파일 경로 유래)에 네임스페이스가 들어 있어 match 패턴으로 분기됩니다. 실전 응용: prod 네임스페이스 → 장기 보존 저장소, dev → 단기/폐기, 감사 대상 → S3 아카이브 — **같은 수집기가 라우팅 테이블로 여러 정책을** 처리합니다(OUTPUT의 match가 라우팅 테이블).

## 5. 자기 관측 첫걸음

```bash
kubectl -n monitoring port-forward ds/fluent-bit 2020:2020 &
sleep 2
curl -s localhost:2020/api/v1/metrics/prometheus | grep -E "fluentbit_(input|output)_(records|proc_records)_total" | head -4
# fluentbit_input_records_total{name="tail.0"} 1234        ← 읽은 양
# fluentbit_output_proc_records_total{name="stdout.0"} 890 ← 보낸 양
kill %1
```

**읽기** — input과 output의 차이가 크게 벌어지면? 필터로 걸렀거나(정상) 버퍼에 적체 중(주의)입니다. 이 메트릭들이 08에서 Prometheus에 수집되어 "드롭 알림"이 됩니다 — lab-02에서 dropped를 직접 만들어 봅니다.

## 6. 정리

```bash
# 클러스터·릴리스는 lab-02에서 계속
kubectl delete ns shop --wait=false 2>/dev/null || true
```

## 정리

- helm DaemonSet 배포 → 노드의 모든 컨테이너 로그가 파이프라인에
- 세 층 검증: CRI 벗기기(cri 파서) → JSON 승격(Merge_Log) → 메타데이터(kubernetes 필터)
- grep 필터 한 줄 = 하루 수십만 건 소음 절감 (전송·저장·인덱싱 전부) — 단, 지나친 필터링 경계
- tag/match = 라우팅 테이블 — 네임스페이스별 다른 목적지·보존 정책
- **★ 02의 지식(CRI·구조화)이 설정 항목의 "이유"였습니다 — 원리를 알면 설정은 번역입니다**
