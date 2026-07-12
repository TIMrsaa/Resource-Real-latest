# Lab 01 — 인덱스 설계·파이프라인 연결·검색

> OpenSearch를 띄우고(로컬 컨테이너 기본 — 비용 0, AWS 관리형 경로 병기), Fluent Bit의 세 번째 목적지로 연결하고, 역색인의 힘(복합 조건 즉시 검색)과 비용(매핑·색인 통제)을 체감합니다.

## 0. 준비 — 두 경로

```bash
# 경로 A (기본, 비용 0): kind 안에 단일 노드 OpenSearch (학습용)
kind create cluster --name opensearch
kubectl create namespace logging
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: opensearch, namespace: logging }
spec:
  replicas: 1
  selector: { matchLabels: { app: opensearch } }
  template:
    metadata: { labels: { app: opensearch } }
    spec:
      containers:
        - name: os
          image: opensearchproject/opensearch:2
          env:
            - { name: discovery.type, value: single-node }
            - { name: DISABLE_SECURITY_PLUGIN, value: "true" }   # 학습용!
            - { name: OPENSEARCH_JAVA_OPTS, value: "-Xms512m -Xmx512m" }
          ports: [{ containerPort: 9200 }]
---
apiVersion: v1
kind: Service
metadata: { name: opensearch, namespace: logging }
spec: { selector: { app: opensearch }, ports: [{ port: 9200 }] }
EOF
kubectl -n logging rollout status deploy/opensearch --timeout=300s

# 경로 B (AWS 관리형 — 비용 발생!): OpenSearch Service 도메인 생성 후
#   Fluent Bit output에 AWS_Auth On + IRSA (14 패턴) — 이하 동일 개념
```

## 1. 매핑 통제 — 색인할 것을 고릅니다

동적 매핑에 맡기지 않고 템플릿으로 설계합니다(theory 2절):

```bash
kubectl -n logging port-forward svc/opensearch 9200:9200 &
sleep 3

curl -s -X PUT localhost:9200/_index_template/logs-app -H 'Content-Type: application/json' -d '{
  "index_patterns": ["logs-app-*"],
  "template": {
    "settings": { "number_of_shards": 1, "number_of_replicas": 0 },
    "mappings": {
      "dynamic": "strict",
      "properties": {
        "@timestamp": { "type": "date" },
        "level":      { "type": "keyword" },
        "event":      { "type": "keyword" },
        "user_id":    { "type": "keyword" },
        "trace_id":   { "type": "keyword", "index": false },
        "message":    { "type": "text" },
        "kubernetes": { "type": "object", "dynamic": true }
      }
    }
  }
}'
```

**설계 읽기** — ① `dynamic: strict`: 선언 안 한 필드는 거부(매핑 폭발 차단), ② level/event는 keyword(정확 일치·집계용 — 토큰화 불필요), ③ trace_id는 `index: false`(저장하되 색인 안 함 — trace_id로 "검색"할 일은 12의 derived fields가 하므로 여기선 색인 값을 안 냄), ④ message만 text(풀텍스트). **색인의 절제가 곧 설계**입니다 — 네 번째 반복(03 라벨→12 Loki→17 annotation→18 매핑).

## 2. Fluent Bit — 세 번째 목적지

```bash
# 02 lab-02의 JSON 로그 앱 재사용
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment
  labels: { app: payment }
spec:
  replicas: 1
  selector:
    matchLabels: { app: payment }
  template:
    metadata:
      labels: { app: payment }
    spec:
      containers:
        - name: payment
          image: busybox
          command:
            - sh
            - -c
            - |
              while true; do
                u=$((RANDOM % 50));
                if [ $((RANDOM % 4)) -eq 0 ]; then
                  echo "{\"level\":\"error\",\"event\":\"pg_timeout\",\"user_id\":\"u$u\",\"message\":\"gateway timeout after 3 retries\"}";
                else
                  echo "{\"level\":\"info\",\"event\":\"payment_ok\",\"user_id\":\"u$u\",\"message\":\"payment processed normally\"}";
                fi; sleep 0.3;
              done
EOF

helm repo add fluent https://fluent.github.io/helm-charts 2>/dev/null; helm repo update
cat > /tmp/fb-os.yaml <<'EOF'
config:
  inputs: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/payment*.log
        Tag               kube.*
        multiline.parser  cri
        DB                /var/log/flb_os.db
  filters: |
    [FILTER]
        Name              kubernetes
        Match             kube.*
        Merge_Log         On
        Keep_Log          Off
  outputs: |
    [OUTPUT]
        Name              opensearch
        Match             kube.*
        Host              opensearch.logging.svc.cluster.local
        Port              9200
        Index             logs-app-2026.07.11
        Suppress_Type_Name On
        Trace_Error       On
EOF
helm install fluent-bit fluent/fluent-bit -n logging -f /tmp/fb-os.yaml
kubectl -n logging rollout status ds/fluent-bit --timeout=120s
sleep 30
```

```bash
# strict 매핑과 실제 레코드의 충돌 관찰 (교육 포인트!)
kubectl -n logging logs ds/fluent-bit | grep -i "error" | tail -3
# 400 mapping 거부가 보인다면: kubernetes.* 외 예상 밖 필드 때문
# → 실전 절충: 최상위는 strict, 자유 영역(kubernetes)은 dynamic true (템플릿 참고)
#   또는 Fluent Bit filter로 필드 정리 후 전송 — "계약(02)"이 여기서도 중요
```

## 3. 역색인의 힘 — 복합 조건 즉시

```bash
curl -s localhost:9200/logs-app-*/_count | head -c 100   # 색인된 수

# 복합 조건: error AND 특정 유저 AND 메시지에 "retries"
curl -s localhost:9200/logs-app-*/_search -H 'Content-Type: application/json' -d '{
  "query": { "bool": { "must": [
    { "term": { "level": "error" } },
    { "term": { "user_id": "u7" } },
    { "match": { "message": "retries" } }
  ]}},
  "size": 2
}' | head -c 500
# 즉시 응답 — 라벨에 없는 필드 조합인데도! (Loki라면 grep 구간)

# 집계: 유저별 에러 상위 (02의 그 질문 — 네 번째 도구로)
curl -s localhost:9200/logs-app-*/_search -H 'Content-Type: application/json' -d '{
  "size": 0,
  "query": { "term": { "level": "error" } },
  "aggs": { "by_user": { "terms": { "field": "user_id", "size": 5 } } }
}' | python3 -m json.tool | grep -A2 '"key"' | head -15
# 유저별 카운트 즉시 — aggregation의 힘
```

**대비 체감** — 12의 Loki에서 이 질문은 `| json | ...` 파이프라인(청크 스캔)이었습니다. 여기선 역색인이 즉답합니다 — 대신 그 색인을 만드는 쓰기 비용을 상시 내고 있는 것입니다. "쓰기 최적 vs 읽기 최적"의 실감.

## 4. 색인 비용의 물증

```bash
# 인덱스 크기 확인 — 원본 대비 얼마나 커졌나
curl -s 'localhost:9200/_cat/indices/logs-app-*?v&h=index,docs.count,store.size'
# store.size가 원본 로그 합계보다 큰 것을 확인 (역색인+원본 저장)
# → Loki의 압축 청크와 대비되는 저장 프로파일
```

## 5. 정리

```bash
kill %1 2>/dev/null || true
# 클러스터는 lab-02(ISM·판단)에서 계속
```

## 정리

- 매핑 템플릿 = 색인의 설계: strict·keyword/text·index:false — "다 색인"이 기본값의 함정
- Fluent Bit 세 번째 목적지 — 06·07의 파이프라인 재사용 (관리형은 +SigV4/IRSA)
- strict와 실제 레코드의 충돌 = 계약(02)의 중요성 재확인 — 절충 설계(자유 영역 분리)
- 복합 조건·집계 즉답의 힘 vs 인덱스 크기·쓰기 비용의 물증 — 쓰기 최적(Loki) vs 읽기 최적(OS)
- **★ 색인의 절제가 설계 — 03·12·17에 이은 네 번째 반복 (같은 물리, 다른 이름)**
