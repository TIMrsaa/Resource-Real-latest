# Lab 01 — 차트 제작과 환경 분리

## Step 1. 스캐폴드 생성과 해부

```bash
mkdir -p ~/helm-lab && cd ~/helm-lab
helm create webapp
find webapp -type f | sort
```

`helm create`가 만들어준 견본은 그 자체로 모범 사례 모음입니다. 특히 `templates/_helpers.tpl`과 deployment.yaml의 구조를 정독하세요 — 이 커리큘럼에서 배운 것들(표준 라벨, probe, SA, HPA 조건부)이 다 들어 있습니다.

## Step 2. 렌더링 먼저 — 템플릿과 친해지기

```bash
helm template test ./webapp | head -50          # 기본 values로 렌더링
helm template test ./webapp --set replicaCount=3 | grep replicas
helm template test ./webapp --set autoscaling.enabled=true | grep -A2 "kind: HorizontalPodAutoscaler" | head -5
helm template test ./webapp --set autoscaling.enabled=true | grep "replicas:" || echo "replicas 없음!"
```

✅ 마지막 명령: autoscaling을 켜면 Deployment에서 **replicas가 사라집니다** — 모듈 13 pitfall("HPA vs YAML replicas")이 차트 레벨에서 해결된 모습. deployment.yaml의 해당 if문을 찾아 확인하세요.

## Step 3. 우리 앱에 맞게 수정

values.yaml에서 이미지/포트를 우리 실습용으로:

```bash
cd webapp
# values.yaml 수정 (에디터로 직접 또는):
python3 - <<'EOF' 2>/dev/null || sed -i \
  -e 's|repository: nginx|repository: registry.k8s.io/e2e-test-images/agnhost|' \
  -e 's|tag: ""|tag: "2.53"|' values.yaml
EOF
```

templates/deployment.yaml의 containers에 args와 환경별 메시지 추가 (containers의 image: 줄 아래에):

```yaml
          args: ["netexec", "--http-port={{ .Values.service.targetPort | default 8080 }}"]
          env:
            - name: ENVIRONMENT
              value: {{ .Values.environment | quote }}
```

values.yaml 맨 위에 추가:
```yaml
environment: dev
```

service.port가 컨테이너 8080을 가리키도록 values.yaml의 service 섹션 확인/수정:
```yaml
service:
  type: ClusterIP
  port: 80
  targetPort: 8080
```

(templates/service.yaml의 targetPort가 `http`라면 `{{ .Values.service.targetPort }}`로, deployment의 containerPort도 동일하게 맞춥니다 — **렌더링으로 확인하며** 진행하세요: `helm template . | grep -B2 -A6 "kind: Service"`)

```bash
helm lint .
```

예상: `1 chart(s) linted, 0 chart(s) failed`

## Step 4. 환경별 values 파일

```bash
cat > values-dev.yaml <<'EOF'
environment: dev
replicaCount: 1
resources:
  requests: { cpu: 50m, memory: 64Mi }
EOF

cat > values-prod.yaml <<'EOF'
environment: prod
replicaCount: 3
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 10
  targetCPUUtilizationPercentage: 60
resources:
  requests: { cpu: 200m, memory: 128Mi }
  limits: { memory: 256Mi }
EOF

# 같은 차트, 두 환경 — 렌더링 비교
diff <(helm template t . -f values-dev.yaml) <(helm template t . -f values-prod.yaml) | head -30
```

✅ diff에 replicas/HPA/resources 차이만 보입니다 — **공통은 한 곳(차트), 차이는 주문서(values)** 가 달성됐습니다.

## Step 5. 실제 설치

```bash
helm install webapp-dev . -f values-dev.yaml -n helm-dev --create-namespace
helm install webapp-prod . -f values-prod.yaml -n helm-prod --create-namespace

helm list -A | grep webapp
kubectl get deploy,hpa -n helm-prod
```

예상: dev에는 Deployment(1 replica), prod에는 Deployment+HPA. NOTES.txt 출력(접속 안내)도 읽어보세요 — 그것도 템플릿입니다.

```bash
# 동작 확인
kubectl run curl --rm -it --image=public.ecr.aws/docker/library/busybox:stable --restart=Never -- \
  wget -qO- http://webapp-prod.helm-prod/hostname
```

## 정리

릴리스들은 lab-02에서 계속 사용.
