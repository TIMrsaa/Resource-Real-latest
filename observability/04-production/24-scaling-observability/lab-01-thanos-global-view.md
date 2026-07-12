# Lab 01 — Thanos: 두 클러스터의 메트릭을 한 화면에

> kind 클러스터 하나 안에 "두 클러스터"(네임스페이스로 분리된 두 Prometheus)를 흉내 내고, Thanos sidecar + MinIO(오브젝트 스토리지) + Query로 글로벌 뷰를 구축합니다 — 대규모 관측의 뼈대를 손으로.

## 0. 준비

```bash
kind create cluster --name thanos

# MinIO — S3 흉내 (오브젝트 스토리지)
kubectl create namespace storage
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: minio, namespace: storage }
spec:
  replicas: 1
  selector: { matchLabels: { app: minio } }
  template:
    metadata: { labels: { app: minio } }
    spec:
      containers:
        - name: minio
          image: minio/minio:latest
          args: ["server", "/data"]
          env:
            - { name: MINIO_ROOT_USER, value: thanos }
            - { name: MINIO_ROOT_PASSWORD, value: thanos-secret }
          ports: [{ containerPort: 9000 }]
---
apiVersion: v1
kind: Service
metadata: { name: minio, namespace: storage }
spec: { selector: { app: minio }, ports: [{ port: 9000 }] }
EOF
kubectl -n storage rollout status deploy/minio --timeout=120s

# 버킷 생성
kubectl -n storage run mc --image=minio/mc --restart=Never --command -- sh -c '
  mc alias set m http://minio.storage.svc:9000 thanos thanos-secret &&
  mc mb m/thanos-blocks'
sleep 15
```

## 1. "두 클러스터" — Prometheus × 2 + sidecar

```bash
# 오브젝트 스토리지 설정 (양쪽 공용)
kubectl create namespace cluster-east; kubectl create namespace cluster-west
for ns in cluster-east cluster-west; do
kubectl -n $ns create secret generic thanos-objstore --from-literal=objstore.yml='
type: S3
config:
  bucket: thanos-blocks
  endpoint: minio.storage.svc:9000
  access_key: thanos
  secret_key: thanos-secret
  insecure: true'
done

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null; helm repo update
# east와 west 두 스택 — external_labels로 정체성 부여 (핵심!)
for region in east west; do
cat > /tmp/prom-$region.yaml <<EOF
prometheus:
  prometheusSpec:
    externalLabels:
      cluster: $region                    # ★ 글로벌 뷰에서 구분할 라벨
    retention: 6h                          # 로컬은 짧게 — 장기는 스토리지로
    thanos:                                # ★ Operator가 sidecar를 붙여줍니다
      objectStorageConfig:
        existingSecret: { name: thanos-objstore, key: objstore.yml }
grafana: { enabled: false }
alertmanager: { enabled: false }
EOF
helm install prom-$region prometheus-community/kube-prometheus-stack \
  -n cluster-$region -f /tmp/prom-$region.yaml
done
kubectl -n cluster-east rollout status statefulset -l app.kubernetes.io/name=prometheus --timeout=300s
kubectl -n cluster-west rollout status statefulset -l app.kubernetes.io/name=prometheus --timeout=300s

# sidecar 확인 — Prometheus Pod에 thanos-sidecar 컨테이너가!
kubectl -n cluster-east get pod -l app.kubernetes.io/name=prometheus \
  -o jsonpath='{.items[0].spec.containers[*].name}'
# prometheus config-reloader thanos-sidecar   ← 무침습 부착 (08 체계 그대로)
```

## 2. Thanos Query — 하나의 창구

```bash
kubectl create namespace thanos
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: thanos-query, namespace: thanos }
spec:
  replicas: 1
  selector: { matchLabels: { app: thanos-query } }
  template:
    metadata: { labels: { app: thanos-query } }
    spec:
      containers:
        - name: query
          image: quay.io/thanos/thanos:v0.35.0
          args:
            - query
            - --http-address=0.0.0.0:9090
            - --endpoint=dnssrv+_grpc._tcp.prom-east-kube-prometheus-thanos-discovery.cluster-east.svc
            - --endpoint=dnssrv+_grpc._tcp.prom-west-kube-prometheus-thanos-discovery.cluster-west.svc
          ports: [{ containerPort: 9090 }]
---
apiVersion: v1
kind: Service
metadata: { name: thanos-query, namespace: thanos }
spec: { selector: { app: thanos-query }, ports: [{ port: 9090 }] }
EOF
kubectl -n thanos rollout status deploy/thanos-query --timeout=120s
```

## 3. 글로벌 뷰 확인 — 한 쿼리로 두 클러스터

```bash
kubectl -n thanos port-forward svc/thanos-query 9090:9090 &
sleep 3

# 하나의 PromQL로 두 클러스터의 같은 메트릭이 — cluster 라벨로 구분되어
curl -s 'localhost:9090/api/v1/query?query=count(up)%20by%20(cluster)' | head -c 400
# {"metric":{"cluster":"east"},"value":[...,"N"]}
# {"metric":{"cluster":"west"},"value":[...,"M"]}
#  ↑ ★ 글로벌 뷰! "전 클러스터의 payment 에러율"이 이렇게 한 쿼리가 됩니다

# 어느 소스가 연결됐나 (Query의 스토어 목록)
curl -s 'localhost:9090/api/v1/stores' 2>/dev/null | head -c 300 || true
```

**구조 읽기** — Query가 두 sidecar에 팬아웃해 병합했습니다. external_labels(cluster)가 구분자 — **글로벌 뷰의 전제는 정체성 라벨의 규율**입니다(붙이지 않으면 두 클러스터의 시계열이 뒤섞여 구분 불가). 03의 라벨 규율이 멀티클러스터에서 또 한 번.

## 4. 장기 저장 확인 — 블록이 바다로

```bash
# sidecar는 2시간 블록 완성 시 업로드 — 실습에선 시간이 걸리므로 확인 위주
kubectl -n storage run mc2 --image=minio/mc --restart=Never --command -- sh -c '
  mc alias set m http://minio.storage.svc:9000 thanos thanos-secret &&
  mc ls -r m/thanos-blocks | head -5'
sleep 10; kubectl -n storage logs mc2
# (2h 경과 후) <ULID>/chunks/... meta.json ...  ← TSDB 블록이 스토리지에!
# 로컬 retention 6h가 지나도 스토리지의 블록은 남습니다 —
#   Store Gateway를 붙이면 그 과거가 쿼리 가능 (구조 완성의 다음 조각)
```

**의미** — 로컬 디스크의 벽(08)이 사라지는 순간입니다: 보존이 "디스크 크기"가 아니라 "스토리지 정책"의 문제로. Compactor가 이 블록들을 압축·다운샘플해 몇 년치 쿼리도 가볍게 만듭니다(theory 2절 — 실습에선 구조 이해까지).

## 5. 정리

```bash
kill %1 2>/dev/null || true
# 클러스터는 lab-02에서 계속
```

## 정리

- "두 클러스터"의 Prometheus에 sidecar 무침습 부착 — 08의 수집 체계 그대로
- external_labels(cluster)가 글로벌 뷰의 구분자 — 정체성 라벨의 규율이 전제
- Thanos Query = 하나의 PromQL 창구 — 팬아웃·병합으로 "count(up) by (cluster)"
- 블록이 오브젝트 스토리지로 — 보존이 디스크에서 정책의 문제로 (08의 벽 해체)
- **★ 대규모의 뼈대: 로컬은 그대로, 옆(sidecar)과 위(Query)와 뒤(스토리지)를 더합니다**
