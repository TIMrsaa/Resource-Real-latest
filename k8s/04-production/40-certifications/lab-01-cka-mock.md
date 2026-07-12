# Lab 01 — CKA형 모의 7문 (제한 50분)

> **규칙**: 타이머 50분. 문제당 막히면 5분에 끊고 다음. 풀이는 맨 아래 — 먼저 보지 말 것.
> 준비: `kubectl create ns exam` (모든 문제는 exam ns, 표기 없으면)

---

**문제 1 (4분).** `redis-prod`라는 Pod를 만들라: 이미지 `public.ecr.aws/docker/library/redis:7`, 컨테이너 포트 6379, 라벨 `tier=db`. Pod가 Running인지 확인하세요.

**문제 2 (6분).** Deployment `webapp`(이미지 nginx:1.27, replicas 3)을 만들고, 이미지를 nginx:1.28로 롤링 업데이트한 뒤, **업데이트 이력에 남긴 채** 다시 1.27로 롤백하세요. 현재 이미지를 출력해 검증.

**문제 3 (7분).** ServiceAccount `viewer`를 만들고, exam ns의 Pod를 get/list/watch만 할 수 있는 Role `pod-reader`와 RoleBinding을 만들라. `auth can-i`로 (허용 1, 거부 1) 두 가지를 검증하세요.

**문제 4 (7분).** Deployment `webapp`을 port 80으로 노출하는 ClusterIP Service `webapp-svc`를 만들고, 임시 Pod에서 Service 이름으로 호출해 검증하세요. 그 후 NodePort 30080으로 변경하세요.

**문제 5 (8분).** 노드 하나를 골라 `disktype=ssd` 라벨을 붙이고, 그 노드에만 스케줄되는 Pod `pinned`(busybox, sleep 3600)를 nodeSelector로 만들라. 배치 확인 후 — 노드 라벨을 지우면 이미 떠 있는 pinned는 어떻게 되는가요? (답을 적고 확인)

**문제 6 (8분).** 다음 장애를 수리하세요:
```bash
kubectl apply -n exam -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: broken }
spec:
  replicas: 2
  selector: { matchLabels: { app: broken } }
  template:
    metadata: { labels: { app: broken } }
    spec:
      containers:
      - name: web
        image: public.ecr.aws/nginx/nginx:1.99-typo
        readinessProbe: { httpGet: { path: /, port: 8080 } }
EOF
```
두 가지 문제를 모두 찾아 고치고, READY 2/2를 검증하세요.

**문제 7 (10분).** exam ns에 ① 기본 거부(Ingress) NetworkPolicy ② 라벨 `role=client`인 Pod만 webapp-svc의 백엔드(port 80)에 접근 허용하는 정책을 만들라. 허용/차단 각 1회 검증.

---
---

## 풀이 (자기 채점)

**1.**
```bash
k run redis-prod -n exam --image=public.ecr.aws/docker/library/redis:7 --port=6379 -l tier=db
k get pod redis-prod -n exam    # Running
```
생성기 한 줄로 끝 — YAML 파일을 만들었으면 시간 손해.

**2.**
```bash
k create deploy webapp -n exam --image=public.ecr.aws/nginx/nginx:1.27 --replicas=3
k set image deploy/webapp -n exam nginx=public.ecr.aws/nginx/nginx:1.28
k rollout status deploy/webapp -n exam
k rollout undo deploy/webapp -n exam            # 이력에 남는 롤백 (rollout history로 확인)
k get deploy webapp -n exam -o jsonpath='{.spec.template.spec.containers[0].image}'  # 1.27
```

**3.**
```bash
k create sa viewer -n exam
k create role pod-reader -n exam --verb=get,list,watch --resource=pods
k create rolebinding viewer-rb -n exam --role=pod-reader --serviceaccount=exam:viewer
k auth can-i list pods -n exam --as=system:serviceaccount:exam:viewer        # yes
k auth can-i delete pods -n exam --as=system:serviceaccount:exam:viewer      # no
```
RBAC도 전부 생성기 — 모듈 11에서 손에 붙인 그것.

**4.**
```bash
k expose deploy webapp -n exam --name=webapp-svc --port=80 --target-port=80
k run t -n exam --rm -it --restart=Never --image=public.ecr.aws/docker/library/busybox:stable \
  -- wget -qO- -T3 http://webapp-svc | head -2
k patch svc webapp-svc -n exam -p '{"spec":{"type":"NodePort","ports":[{"port":80,"nodePort":30080}]}}'
k get svc webapp-svc -n exam     # TYPE: NodePort, 30080
```

**5.**
```bash
NODE=$(k get nodes -o jsonpath='{.items[0].metadata.name}')
k label node $NODE disktype=ssd
k run pinned -n exam --image=public.ecr.aws/docker/library/busybox:stable \
  --overrides='{"spec":{"nodeSelector":{"disktype":"ssd"}}}' -- sleep 3600
k get pod pinned -n exam -o wide          # 그 노드에 배치
k label node $NODE disktype-
k get pod pinned -n exam                  # 그대로 Running!
```
답: **이미 떠 있는 Pod는 영향 없습니다** — nodeSelector는 스케줄 시점에만 평가(모듈 12). 재생성될 때만 Pending이 됩니다.

**6.**
```bash
k get pods -n exam -l app=broken                        # ImagePullBackOff 발견
k describe pod -n exam -l app=broken | grep -i failed | head -2   # 태그 오타 확정
k set image deploy/broken -n exam web=public.ecr.aws/nginx/nginx:1.27
k get pods -n exam -l app=broken                        # Running인데 READY 0/1 — 두 번째 문제
k get endpoints -n exam 2>/dev/null; k describe pod -n exam -l app=broken | grep -i unhealthy | head -1
# readiness가 8080인데 nginx는 80 — 수정:
k patch deploy broken -n exam --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/port","value":80}]'
k get deploy broken -n exam               # READY 2/2
```
모듈 38의 루틴 그대로: 이미지 사유 문장 → Running≠Ready → probe 대조.

**7.**
```bash
k apply -n exam -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny }
spec: { podSelector: {}, policyTypes: [Ingress] }
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-client }
spec:
  podSelector: { matchLabels: { app: webapp } }
  policyTypes: [Ingress]
  ingress:
  - from: [{ podSelector: { matchLabels: { role: client } } }]
    ports: [{ port: 80 }]
EOF
k run t1 -n exam --rm -it --restart=Never --image=public.ecr.aws/docker/library/busybox:stable \
  -- sh -c 'wget -qO- -T3 http://webapp-svc || echo BLOCKED'                       # BLOCKED
k run t2 -n exam --rm -it --restart=Never -l role=client \
  --image=public.ecr.aws/docker/library/busybox:stable -- wget -qO- -T3 http://webapp-svc | head -1   # 성공
```

## 채점과 복기

- 7문제 × 검증까지 = 50분 안에 5문제 이상이면 합격권 페이스
- 막힌 문제는 **해당 모듈로 돌아가지 말고**, 먼저 풀이의 명령을 3회 반복해 손에 붙인 뒤 모듈을 복습하세요 (시험 대비는 손이 먼저입니다)

```bash
kubectl delete ns exam    # lab-02 전에 초기화
```
