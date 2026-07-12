# Lab 01 — base/overlay로 dev/prod 분리

## Step 1. base 구축 (완전한 YAML)

```bash
mkdir -p ~/kustomize-lab/{base,overlays/dev,overlays/prod} && cd ~/kustomize-lab

cat > base/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 1
  selector:
    matchLabels: { app: web }
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
      - name: web
        image: registry.k8s.io/e2e-test-images/agnhost:2.53
        args: ["netexec", "--http-port=8080"]
        ports: [{ containerPort: 8080 }]
        readinessProbe:
          httpGet: { path: /healthz, port: 8080 }
EOF

cat > base/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector: { app: web }
  ports: [{ port: 80, targetPort: 8080 }]
EOF

cat > base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
labels:
- pairs: { app.kubernetes.io/managed-by: kustomize }
  includeSelectors: false
EOF

kubectl kustomize base | head -20      # base 자체도 빌드 가능 (완전한 YAML이므로)
```

## Step 2. dev 오버레이 — 최소 패치

```bash
cat > overlays/dev/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
namespace: kz-dev
nameSuffix: -dev
EOF

kubectl kustomize overlays/dev | grep -E "name:|namespace:|replicas:"
```

예상: 이름이 `web-dev`, ns가 `kz-dev`. **base 파일은 1바이트도 안 바뀌었습니다.**

## Step 3. prod 오버레이 — 패치 2형식 모두 사용

```bash
cat > overlays/prod/replicas-patch.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 3
EOF

cat > overlays/prod/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../../base
namespace: kz-prod
patches:
- path: replicas-patch.yaml                  # strategic merge
- target: { kind: Deployment, name: web }    # JSON6902
  patch: |-
    - op: add
      path: /spec/template/spec/containers/0/resources
      value:
        requests: { cpu: 200m, memory: 128Mi }
        limits: { memory: 256Mi }
    - op: add
      path: /spec/template/spec/topologySpreadConstraints
      value:
      - maxSkew: 1
        topologyKey: topology.kubernetes.io/zone
        whenUnsatisfiable: ScheduleAnyway
        labelSelector: { matchLabels: { app: web } }
EOF

# 환경 차이를 diff로 한눈에
diff <(kubectl kustomize overlays/dev) <(kubectl kustomize overlays/prod)
```

✅ diff에 replicas/resources/spread/ns만 나옵니다 — 모듈 12(spread), 09(requests)에서 배운 운영 표준이 **prod에만** 패치로 강제된 모습. 이것이 Kustomize식 환경 분리.

## Step 4. 적용과 검증

```bash
kubectl create ns kz-dev kz-prod
kubectl apply -k overlays/dev
kubectl apply -k overlays/prod
kubectl get deploy -A | grep -E "kz-"
```

예상:
```
kz-dev    web-dev   1/1
kz-prod   web       3/3
```

```bash
# 어느 오버레이가 만든 것인지 라벨로 추적 가능
kubectl get deploy -n kz-prod web -o jsonpath='{.metadata.labels}'
```

## Step 5. CI 관점 — images 필드

```bash
cd overlays/prod
# CI가 새 이미지를 박을 때 sed가 아니라:
kubectl kustomize . | grep image:
cat >> kustomization.yaml <<'EOF'
images:
- name: registry.k8s.io/e2e-test-images/agnhost
  newTag: "2.52"
EOF
kubectl kustomize . | grep image:
cd ../..
```

예상: 태그가 2.52로 바뀌어 렌더링. `kustomize edit set image foo=bar:tag` 명령형도 있어 파이프라인에서 한 줄로 씁니다 (cicd 파트에서 재등장).

## 정리

리소스는 lab-02에서 계속 사용.
