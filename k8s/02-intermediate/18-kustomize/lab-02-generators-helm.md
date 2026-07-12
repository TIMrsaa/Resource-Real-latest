# Lab 02 — 해시 제너레이터와 Helm 조합

## Step 1. configMapGenerator — 자동 롤링의 마법

base에 설정과 제너레이터 추가:

```bash
cd ~/kustomize-lab
cat > base/app.properties <<'EOF'
color=blue
mode=normal
EOF

# base/kustomization.yaml에 추가
cat >> base/kustomization.yaml <<'EOF'
configMapGenerator:
- name: app-config
  files: [app.properties]
EOF

# base/deployment.yaml의 containers에 volumeMount 참조 추가
python3 - <<'EOF' 2>/dev/null || true
EOF
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
      volumes:
      - name: config
        configMap: { name: app-config }     # ← 제너레이터가 이 이름을 해시 이름으로 바꿔줍니다
      containers:
      - name: web
        image: registry.k8s.io/e2e-test-images/agnhost:2.53
        args: ["netexec", "--http-port=8080"]
        ports: [{ containerPort: 8080 }]
        readinessProbe:
          httpGet: { path: /healthz, port: 8080 }
        volumeMounts:
        - { name: config, mountPath: /etc/config }
EOF

kubectl kustomize overlays/prod | grep -E "name: app-config"
```

예상 출력:
```
  name: app-config-7f9h2k4tm5      ← ConfigMap 이름에 내용 해시!
        name: app-config-7f9h2k4tm5   ← Deployment의 참조도 자동으로 같은 이름!
```

## Step 2. 설정 변경 = 자동 롤링 업데이트 검증

```bash
kubectl apply -k overlays/prod
kubectl get rs -n kz-prod          # RS 1개 기록

# 설정만 변경
sed -i 's/color=blue/color=red/' base/app.properties
kubectl apply -k overlays/prod
kubectl get rs -n kz-prod
```

예상 출력:
```
web-xxxxx   3   3   3      ← 새 RS!
web-yyyyy   0   0   0      ← 옛 RS (롤백용)
```

✅ **ConfigMap 내용만 바꿨는데 롤링 업데이트가 일어났습니다.** 사슬: 내용 변경 → 해시 변경 → CM 이름 변경 → Pod template 변경 → Deployment 컨트롤러가 새 RS. 모듈 07의 "환경변수 갱신 안 됨" 문제와 immutable 패턴이 한 번에 해결되는 메커니즘입니다.

```bash
kubectl get configmap -n kz-prod    # 옛/새 CM이 공존 (옛 RS의 롤백 가능성 보존)
```

## Step 3. Helm 출력에 Kustomize 후처리 — 분업 패턴

시나리오: 외부 차트(우리가 모듈 17에서 만든 webapp으로 대체)를 받되, **회사 표준 라벨과 리소스 정책을 강제**하고 싶습니다. 차트는 수정 권한이 없다고 가정.

```bash
mkdir -p helm-hybrid && cd helm-hybrid
# ① 차트 렌더링 결과를 base로
helm template corp-app ~/helm-lab/webapp --set environment=prod > rendered.yaml

cat > kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- rendered.yaml
namespace: kz-prod
labels:
- pairs:
    corp.example.com/cost-center: "team-shop"     # 회사 비용 추적 라벨 강제
  includeSelectors: false
patches:
- target: { kind: Deployment }
  patch: |-
    - op: add
      path: /spec/template/spec/automountServiceAccountToken
      value: false
EOF

kubectl kustomize . | grep -E "cost-center|automountServiceAccountToken"
```

예상: 차트가 모르는 회사 정책 2가지(비용 라벨, 토큰 마운트 차단 — 모듈 11)가 모든 리소스에 주입됐습니다.

✅ **Helm(제품 설치) + Kustomize(회사 정책 후처리)** — 두 도구의 실무 분업 완성. GitOps 도구들이 이 패턴을 1급으로 지원합니다.

## Step 4. 선택 기준 정리 (체크리스트)

```
우리 팀 앱 + 환경 2~3개          → Kustomize 단독으로 충분
배포 가능한 제품/사내 공용 차트     → Helm (패키징, values 인터페이스, hook)
외부 차트 + 회사 표준 강제         → Helm template + Kustomize
GitOps (ArgoCD/Flux)            → 둘 다 1급 지원 — 위 기준 그대로
```

## 정리

```bash
bash cleanup.sh
```
