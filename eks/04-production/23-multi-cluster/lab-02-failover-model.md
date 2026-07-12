# Lab 02 — 페일오버 모형: "지역 장애"를 만들고 RTO를 재기

Route53 failover의 의미론을 클러스터 안에 축소 모형으로 짓습니다 — 리전 두 개(모형: ns 두 개), 글로벌 라우터(모형: nginx primary/backup), 그리고 **한 리전을 통째로 죽였을 때** 트래픽이 넘어가는 시간을 측정합니다.

> 모형의 정직한 한계: 실물 Route53 failover는 DNS TTL·헬스체크 주기가 지배하고, GA는 anycast로 이를 우회합니다 — 모형은 그 **구조**(헬스 판정→경로 전환)를 배우기 위한 것입니다.

## Step 1. 두 "리전"

```bash
for r in region-a region-b; do
  kubectl create ns $r
  kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: $r
  labels: { app: app }
spec:
  replicas: 1
  selector:
    matchLabels: { app: app }
  template:
    metadata:
      labels: { app: app }
    spec:
      containers:
        - name: podinfo
          image: ghcr.io/stefanprodan/podinfo:6.7.1
          env:
            - name: PODINFO_UI_MESSAGE
              value: $r                    # 어느 "리전"이 응답했는지 표시
---
apiVersion: v1
kind: Service
metadata:
  name: app
  namespace: $r
spec:
  selector: { app: app }
  ports:
    - port: 9898
EOF
done
kubectl rollout status deploy/app -n region-a && kubectl rollout status deploy/app -n region-b
```

## Step 2. 글로벌 라우터 (모형 Route53: primary + failover)

```bash
kubectl create ns global
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata: { name: router-conf, namespace: global }
data:
  default.conf: |
    upstream regions {
      server app.region-a.svc.cluster.local:9898 max_fails=2 fail_timeout=5s;   # primary
      server app.region-b.svc.cluster.local:9898 backup;                        # failover 대상
    }
    server {
      listen 8080;
      location / {
        proxy_pass http://regions;
        proxy_next_upstream error timeout http_502 http_503;   # 실패 시 즉시 다음으로
        proxy_connect_timeout 2s;
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: router, namespace: global }
spec:
  replicas: 1
  selector: { matchLabels: { app: router } }
  template:
    metadata: { labels: { app: router } }
    spec:
      containers:
      - name: nginx
        image: public.ecr.aws/nginx/nginx:1.27
        ports: [{ containerPort: 8080 }]
        volumeMounts: [{ name: conf, mountPath: /etc/nginx/conf.d }]
      volumes: [{ name: conf, configMap: { name: router-conf } }]
---
apiVersion: v1
kind: Service
metadata: { name: router, namespace: global }
spec: { selector: { app: router }, ports: [{ port: 8080 }] }
EOF
kubectl rollout status deploy/router -n global

# 평시: 전부 primary(region-a)로
kubectl run probe --rm -i --restart=Never -n global --image=curlimages/curl -- \
  sh -c 'for i in $(seq 1 5); do curl -s http://router:8080/ | grep -o "region-[ab]"; done'
```

예상: `region-a` × 5 — backup은 잠들어 있습니다 (failover 정책의 평시 모습).

## Step 3. 지역 장애 — 그리고 넘어가는 순간

유입을 흘리는 채로 region-a를 통째로 죽입니다:

```bash
# 터미널 1 — 유입 유지하며 어느 리전이 답하는지 스트림 관찰
kubectl run watcher --rm -i --restart=Never -n global --image=curlimages/curl -- \
  sh -c 'while true; do echo "$(date +%T) $(curl -s -m2 http://router:8080/ | grep -o "region-[ab]" || echo FAIL)"; sleep 0.5; done'

# 터미널 2 — 재해!
kubectl scale deploy/app -n region-a --replicas=0
```

터미널 1 예상:

```
14:02:10 region-a
14:02:11 region-a
14:02:12 FAIL            ← 장애 감지 창 (max_fails × fail_timeout)
14:02:12 region-b        ← 페일오버!
14:02:13 region-b
```

기록: 마지막 region-a ~ 첫 region-b 사이 = **이 모형의 RTO**(수 초). ✅ 구조를 읽어라 — 페일오버 = ① 실패 관측(헬스/에러) ② 판정(임계) ③ 경로 전환. 실물에서 각 단계의 지배 변수: R53은 헬스체크 주기(30s급)+**DNS TTL**(캐시가 옛 답을 기억 — 60s TTL이면 RTO에 그만큼 가산), GA는 anycast라 TTL 항이 사라집니다(theory §3의 표가 이 실험의 확장판).

## Step 4. 복귀 — 그리고 아무도 안 묻는 질문

```bash
kubectl scale deploy/app -n region-a --replicas=1
# watcher 관찰: region-b → region-a로 자동 복귀 (backup 의미론)
```

복귀가 자동인 건 모형이라 그렇습니다 — 실물에선 **failback이 더 위험한 순간**입니다: region-a가 "떴다"와 "데이터가 따라잡았다"는 다른 명제(복제 지연!). 성숙한 runbook은 failback을 수동 게이트로 둡니다.

## Step 5. 남은 8할 체크 (산출물 — 데이터 계층 질문지)

```markdown
# 멀티리전 설계 질문지 — 트래픽은 쉬웠습니다, 이제:
- 쓰기는 어디서? [ ] 단일 리전(복제 읽기) [ ] 멀티 마스터(충돌 규칙: __) [ ] 유저 파티셔닝(cell)
- 복제 지연 허용치(RPO): __ — 페일오버 순간 잃는 트랜잭션의 처리 방침: __
- failback 조건: 데이터 따라잡음 판정 기준 __ + 수동 게이트 담당 __
- 헬스체크 깊이: [ ] 포트 [ ] HTTP 200 [ ] 합성 트랜잭션(권장 — "산 척"을 잡습니다)
- 리허설: 분기 1회 — 이 랩의 Step 3을 실물 스케일로 (36 Game Day의 리전판)
```

## 정리

```bash
bash cleanup.sh
```
