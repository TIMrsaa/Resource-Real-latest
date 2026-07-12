# Lab 01 — APF 관측과 LIST 비용 실측 (공유 EKS)

## Step 1. etcd 위생 점검 — 종류별 객체 수

```bash
# API 서버가 노출하는 "종류별 저장 객체 수" (etcd를 못 봐도 이걸로 충분)
kubectl get --raw /metrics | grep '^apiserver_storage_objects' \
  | sort -t'}' -k2 -rn | head -15
```

예상 출력 (발췌):
```
apiserver_storage_objects{resource="events"} 312
apiserver_storage_objects{resource="pods"} 47
apiserver_storage_objects{resource="secrets"} 41
...
```

✅ **이 표가 "etcd에 뭐가 쌓이는가"의 일일 점검표입니다.** events/pods(시체 포함)/CR이 비정상적으로 크면 위생 문제(theory §2). 운영에선 이 메트릭에 추세 알림을 겁니다.

## Step 2. LIST 비용 — 같은 질문, 다른 가격

```bash
# 관측 표본을 위해 Pod를 좀 만들어두기
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fleet
  labels: { app: fleet }
spec:
  replicas: 60
  selector:
    matchLabels: { app: fleet }
  template:
    metadata:
      labels: { app: fleet }
    spec:
      containers:
        - name: fleet
          image: public.ecr.aws/docker/library/busybox:stable
          command: ["sleep", "3600"]
EOF
kubectl wait --for=condition=Available deploy/fleet --timeout=120s

# ① full LIST — etcd에서 일관 읽기
time kubectl get pods -A -o name > /dev/null
# ② watch cache에서 읽기 (resourceVersion=0)
time kubectl get --raw '/api/v1/pods?resourceVersion=0' > /dev/null
# ③ 페이지네이션 — 500개씩 끊어서
time kubectl get pods -A --chunk-size=500 -o name > /dev/null
```

✅ 이 규모에선 차이가 작지만 **요청이 어디서 응답되는지가 다릅니다**: ①은 etcd, ②는 API 서버 메모리(watch cache). Pod 15만 개 클러스터에서 ①은 GB급 메모리 스파이크, ②③은 생존 가능. 클라이언트 코드를 짤 때(모듈 31) informer가 내부적으로 ②로 시작하는 이유.

## Step 3. 내 요청이 APF의 어느 줄에 서는가

```bash
kubectl get flowschemas | head -12
kubectl get prioritylevelconfigurations
# 내 kubectl 요청이 매칭된 FlowSchema — 응답 헤더에 찍힙니다
kubectl get pods -v=8 2>&1 | grep -i "X-Kubernetes-Pf" | head -2
```

예상:
```
X-Kubernetes-Pf-Flowschema-Uid: ...      (global-default에 매칭)
X-Kubernetes-Pf-Prioritylevel-Uid: ...
```

✅ 관리자(우리)의 kubectl은 보통 `global-default` 또는 `exempt` 계열에 섭니다. kubelet의 요청은 `system-nodes` — **줄이 달라서 우리가 폭주해도 kubelet 하트비트는 안 밀립니다.**

## Step 4. 폭주 시뮬레이션 — APF 큐가 차오르는 것 보기

터미널 1 (관측):
```bash
watch -n2 'kubectl get --raw /metrics | grep -E "apiserver_flowcontrol_current_inqueue_requests|apiserver_flowcontrol_rejected" | grep -v " 0$" | head'
```

터미널 2 (부하 — LIST 폭주 클라이언트 흉내):
```bash
for i in $(seq 1 30); do
  ( for j in $(seq 1 40); do kubectl get pods -A -o name > /dev/null 2>&1; done ) &
done; wait
```

예상 (터미널 1): `current_inqueue_requests{priority_level="global-default"}`가 0에서 출렁이며 올라갑니다. 심하면 `rejected`(429) 카운터 증가.

✅ **폭주가 global-default 줄 안에 갇혔습니다** — 같은 시간 kubelet(system 레벨)은 무풍. APF 도입 전엔 이런 폭주가 control plane 전체를 마비시켰습니다. 429를 봤다면: 부하를 멈추는 게 아니라 **클라이언트 패턴을 고치는 것**(informer)이 정답.

## Step 5. 셀렉터의 매너 — 서버 필터 vs 클라이언트 필터

```bash
# 라벨 셀렉터: API 서버가 걸러서 보냄 (네트워크/직렬화 절약)
time kubectl get pods -A -l app=fleet -o name | wc -l
# 필드 셀렉터: 동일하게 서버 측
kubectl get pods -A --field-selector=status.phase=Running -o name | wc -l
# 나쁜 패턴: 전부 받아서 grep (전체 직렬화 비용을 다 냄)
kubectl get pods -A -o json | grep -c '"app": "fleet"' || true
```

✅ 같은 결과, 다른 청구서. 스크립트/컨트롤러에서 "전부 받아서 내가 거른다"는 대규모에서 범죄가 됩니다.

## 정리

```bash
kubectl delete deployment fleet
```

fleet만 정리. lab-02는 로컬 kind에서 진행합니다.
