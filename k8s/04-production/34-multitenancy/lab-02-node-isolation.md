# Lab 02 — 전용 노드풀: 격리, 침입, 그리고 강제

lab-01의 패키지가 "방"을 만들었다면, 이 랩은 "층"을 나눕니다 — 그리고 층 분리가 taint만으로는 **잠기지 않는 문**임을 침입 실험으로 확인한 뒤, 모듈 23의 정책 엔진으로 잠급니다.

## Step 0. 전제

lab-01의 team-rocket / team-galaxy ns가 살아 있어야 합니다. 노드가 2대 이상인지도 확인:

```bash
kubectl get nodes    # 2대 미만이면 이 랩의 "밀려남" 관찰이 안 됩니다
```

## Step 1. 노드 하나를 team-rocket 전용으로 (taint + label)

```bash
NODES=($(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'))
kubectl taint node ${NODES[0]} tenant=team-rocket:NoSchedule   # 출입 통제
kubectl label node ${NODES[0]} tenant=team-rocket              # 주소 표지판
kubectl get nodes -L tenant
```

taint와 label을 **둘 다** 다는 이유(모듈 12의 복습): taint는 "남을 밀어내는" 장치고, label은 "자기 Pod를 이리로 부르는" affinity의 목적지입니다. 하나는 배제, 하나는 유인 — 방향이 다릅니다.

## Step 2. 관찰 ① — toleration 없는 Pod는 밀려납니다

```bash
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: generic
  namespace: team-galaxy
  labels: { app: generic }
spec:
  replicas: 4
  selector:
    matchLabels: { app: generic }
  template:
    metadata:
      labels: { app: generic }
    spec:
      # PSA baseline 통과용 securityContext (lab-01에서 확인한 그 규칙)
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        seccompProfile: { type: RuntimeDefault }
      containers:
        - name: busybox
          image: public.ecr.aws/docker/library/busybox:stable
          command: ["sleep", "600"]
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
EOF
sleep 10
kubectl get pods -n team-galaxy -l app=generic -o wide | awk 'NR>1{print $7}' | sort | uniq -c
```

예상: 4개 전부 전용 노드가 **아닌** 노드에 몰려 있습니다 — NoSchedule taint가 일반 Pod를 밀어냈습니다.

## Step 3. 관찰 ② — 3종 세트를 갖춘 Pod만 전용 노드에

```bash
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: { name: rocket-app, namespace: team-rocket }
spec:
  replicas: 2
  selector: { matchLabels: { app: rocket-app } }
  template:
    metadata: { labels: { app: rocket-app } }
    spec:
      securityContext: { runAsNonRoot: true, runAsUser: 10001, seccompProfile: { type: RuntimeDefault } }
      tolerations:                # ① 입장권 — taint를 견딥니다
      - { key: tenant, operator: Equal, value: team-rocket, effect: NoSchedule }
      affinity:                   # ② 유인 — 입장권만 있으면 공용 노드로도 갈 수 있으므로
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - { key: tenant, operator: In, values: [team-rocket] }
      containers:
      - name: app
        image: public.ecr.aws/docker/library/busybox:stable
        command: [sleep, "600"]
        securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: ["ALL"] } }
EOF
sleep 10
kubectl get pods -n team-rocket -l app=rocket-app -o wide | awk 'NR>1{print $7}' | sort | uniq -c
```

예상: 2개 전부 `${NODES[0]}`. ✅ **taint(배제) + toleration(입장권) + affinity(유인)** — 모듈 12의 3종 세트가 멀티테넌시의 층 분리 부품으로 재등장했습니다.

## Step 4. 침입 실험 — taint는 잠금이 아닙니다

taint 키는 `kubectl get nodes -o yaml`이면 누구나 봅니다. team-galaxy가 team-rocket의 toleration을 **베껴 쓰면**?

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: sneaky
  namespace: team-galaxy
  labels: { run: sneaky }
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    seccompProfile: { type: RuntimeDefault }
  tolerations:                              # 남의 팀 taint를 견디겠다고 선언
    - key: tenant
      operator: Equal
      value: team-rocket
      effect: NoSchedule
  nodeSelector: { tenant: team-rocket }     # 남의 팀 노드를 지목
  containers:
    - name: sneaky
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "300"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
EOF
sleep 5
kubectl get pod sneaky -n team-galaxy -o wide | awk 'NR>1{print $7}'
```

예상: `${NODES[0]}` — **침입 성공.** team-rocket이 비싸게 확보한 전용 노드에 남의 Pod가 올라탔습니다. 스케줄러는 "toleration이 있는가"만 볼 뿐, "가져도 되는 toleration인가"는 묻지 않습니다.

## Step 5. 잠그기 — admission이 마지막 문을 닫습니다 (모듈 23)

규칙을 CEL 한 줄로: **"tenant toleration을 쓰려면, 그 값이 자기 ns의 tenant 라벨과 같아야 합니다."** 테넌트가 늘어도 정책은 이 하나면 됩니다.

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: tenant-toleration-guard
spec:
  matchConstraints:
    resourceRules:
    - apiGroups: [""]
      apiVersions: ["v1"]
      operations: ["CREATE"]
      resources: ["pods"]
  validations:
  - expression: >-
      !has(object.spec.tolerations) ||
      object.spec.tolerations.all(t,
        !has(t.key) || t.key != 'tenant' ||
        (has(t.value) && t.value == namespaceObject.metadata.labels['tenant']))
    message: "tenant toleration은 자기 네임스페이스의 tenant 라벨 값만 허용됩니다"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: tenant-toleration-guard
spec:
  policyName: tenant-toleration-guard
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchExpressions:
      - { key: tenant, operator: Exists }     # tenant ns에만 적용
EOF

kubectl delete pod sneaky -n team-galaxy --ignore-not-found
sleep 3
# 재침입 시도
kubectl apply -f - 2>&1 <<'EOF' | tail -1
apiVersion: v1
kind: Pod
metadata:
  name: sneaky
  namespace: team-galaxy
  labels: { run: sneaky }
spec:
  tolerations:
    - key: tenant
      operator: Equal
      value: team-rocket
      effect: NoSchedule
  containers:
    - name: sneaky
      image: public.ecr.aws/docker/library/busybox:stable
      command: ["sleep", "300"]
EOF
```

예상: `denied ... tenant toleration은 자기 네임스페이스의...` — 이번엔 API 서버 문턱에서 거부됩니다.

`namespaceObject`에 주목 — VAP는 요청 Pod뿐 아니라 **그 ns 객체까지 CEL에 노출**하므로 "자기 라벨과 대조" 같은 관계 검증이 가능합니다. team-rocket 자신의 Pod(Step 3)는 여전히 통과함도 확인:

```bash
kubectl rollout restart deployment rocket-app -n team-rocket
sleep 10; kubectl get pods -n team-rocket -l app=rocket-app    # Running — 정당한 사용은 그대로
```

✅ **taint(스케줄러의 안내) + admission(API의 강제)** — 두 층이 겹쳐야 "전용"이 계약이 됩니다. 멀티테넌시가 단일 기능이 아니라 여러 모듈의 합작임을 보여주는 이 파트의 절정.

## Step 6. 천장 인식 — 이 랩으로도 안 되는 요구

team-galaxy가 이렇게 요구한다고 합시다:

| 요구 | 되나요? | 이유 |
|------|------|------|
| "전용 노드 주세요" | ✅ 이 랩 | taint+admission |
| "우리만 cert-manager v1.16 쓸게요" | ❌ | CRD는 클러스터 스코프 — 버전은 하나 |
| "우리 전용 admission 웹훅 깔게요" | ❌ | 웹훅 장애가 전 클러스터를 뭅니다 (23) |
| "K8s 1.37로 먼저 올려주세요" | ❌ | control plane은 하나 |

❌들이 쌓이면 ns 멀티테넌시의 천장 — theory §4의 vCluster/클러스터 분리 신호입니다.

## 정리

```bash
bash cleanup.sh
```
