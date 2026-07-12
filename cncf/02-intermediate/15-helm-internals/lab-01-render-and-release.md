# Lab 01 — 렌더링을 해부하고, 릴리스 Secret을 열고, 3-way 병합을 목격합니다

"helm이 내 수동 변경을 되돌린다/안 되돌린다"의 미스터리를 실험으로 확정합니다.

전제: kind, kubectl, helm(v4 권장).

## Step 1. 클러스터와 최소 차트

```bash
kind create cluster --name helm -q
mkdir -p ~/cncf-lab/helm && cd ~/cncf-lab/helm

helm create demo >/dev/null
cd demo
cat > values.yaml <<'EOF'
replicaCount: 2
image:
  repository: nginx
  tag: "1.26"
config:
  logLevel: info
  features:
    - a
    - b
EOF

# 템플릿의 실체를 보여줄 ConfigMap 추가
cat > templates/config.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "demo.fullname" . }}-config
data:
  settings.yaml: |
{{ toYaml .Values.config | indent 4 }}
  level: {{ .Values.config.logLevel | quote }}
EOF
```

## Step 2. 렌더링만 — 클러스터 없이 결과 보기

```bash
helm template demo . | head -40
echo "=== 렌더링 결과에서 ConfigMap만 ==="
helm template demo . | python3 -c "
import sys, yaml
for doc in yaml.safe_load_all(sys.stdin):
    if doc and doc.get('kind')=='ConfigMap':
        print(yaml.dump(doc, allow_unicode=True))
"
```

✅ `toYaml | indent 4`가 중첩 구조를 문자열 블록으로 만들었습니다. **템플릿은 YAML을 문자열로 다룹니다**(theory §4).

## Step 3. 템플릿 함정을 직접 밟기

```bash
# 함정 ①: indent 없이 중첩 값 삽입
cp templates/config.yaml /tmp/config.bak
cat > templates/config.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "demo.fullname" . }}-config
data:
  settings.yaml: {{ toYaml .Values.config }}
EOF
helm template demo . 2>&1 | grep -A3 "settings.yaml" | head -5
echo "→ 여러 줄이 그대로 들어가 YAML이 깨집니다 (또는 이상하게 렌더링)"

# 함정 ②: 타입 — "true"가 bool로 해석
cat > templates/config.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "demo.fullname" . }}-config
data:
  enabled: {{ .Values.config.logLevel }}
EOF
helm template demo . --set config.logLevel=true 2>&1 | grep -A2 "data:" | head -3
echo "→ ConfigMap의 data는 문자열이어야 하는데 bool이 들어가 검증 실패 (quote 필요)"

cp /tmp/config.bak templates/config.yaml
```

```bash
# 방어 도구
helm lint . 2>&1 | tail -3
helm template demo . --debug >/dev/null 2>&1 && echo "✅ 렌더링 OK"
```

## Step 4. 설치 — 그리고 릴리스 Secret을 엽니다

```bash
helm install demo . -n app --create-namespace >/dev/null
kubectl -n app get all | head -6

echo "=== 릴리스는 Secret에 저장됩니다 (theory §2) ==="
kubectl -n app get secret -l owner=helm
SEC=$(kubectl -n app get secret -l owner=helm -o name | head -1)

echo "=== Secret 내용 해부 (base64 → gzip → JSON) ==="
kubectl -n app get $SEC -o jsonpath='{.data.release}' | base64 -d | base64 -d | gunzip | python3 -c "
import json,sys
r = json.load(sys.stdin)
print('name    :', r['name'])
print('version :', r['version'], '(revision)')
print('status  :', r['info']['status'])
print('chart   :', r['chart']['metadata']['name'], r['chart']['metadata']['version'])
print('values  :', json.dumps(r.get('config',{}))[:80])
print('manifest:', len(r['manifest']), 'bytes  ← 렌더링된 전체 매니페스트가 저장됨')
"
```

✅ **릴리스 = 저장된 매니페스트 + values + 메타**. `helm rollback`이 가능한 이유가 여기 있습니다 — 이전 revision의 매니페스트가 통째로 보관되어 있습니다.

## Step 5. 3-way 병합 실험 A — 수동 변경이 살아남는 경우

```bash
echo "현재 replicas: $(kubectl -n app get deploy demo -o jsonpath='{.spec.replicas}')"

# kubectl로 직접 변경
kubectl -n app scale deploy/demo --replicas=5
echo "kubectl로 변경 후: $(kubectl -n app get deploy demo -o jsonpath='{.spec.replicas}')"

# values는 그대로 두고 upgrade (old==new)
helm upgrade demo . -n app >/dev/null
sleep 3
echo "helm upgrade 후: $(kubectl -n app get deploy demo -o jsonpath='{.spec.replicas}')  ← 5가 살아남았습니다!"
```

예상: **5 유지**. old(2) == new(2)이므로 Helm은 replicas를 "변경 없음"으로 보고 live(5)를 건드리지 않습니다(theory §3). 이것이 "helm이 내 수동 변경을 안 되돌렸다"의 정체.

## Step 6. 3-way 병합 실험 B — 수동 변경이 덮이는 경우

```bash
# 이번엔 values를 바꿉니다 (old=2, new=3)
helm upgrade demo . -n app --set replicaCount=3 >/dev/null
sleep 3
echo "values 변경 후: $(kubectl -n app get deploy demo -o jsonpath='{.spec.replicas}')  ← 3으로 덮였다"
```

예상: **3**. old(2) ≠ new(3) → Helm이 그 필드를 관리 대상으로 보고 덮어씁니다. ✅ 같은 필드인데 결과가 다른 이유가 3-way 병합으로 완전히 설명됩니다.

```bash
cat <<'EOF'
정리:
  old(저장) == new(렌더)  → Helm은 그 필드를 "안 건드림" → live의 수동 변경 생존
  old != new              → Helm이 관리 → 수동 변경 덮임
  --force                 → 병합 없이 replace (위험: 다른 컨트롤러의 필드도 날림)

★ HPA를 쓰는 Deployment에서 replicas를 차트에 두면?
  HPA가 live를 바꾸고, values를 만질 때마다 Helm이 되돌립니다 → 진동
  해법: 차트에서 replicas를 제거(HPA가 소유) — cicd 14의 "필드 소유권" 문제와 동일
EOF
```

## Step 7. 히스토리와 롤백

```bash
helm history demo -n app
helm rollback demo 1 -n app >/dev/null
sleep 3
echo "롤백 후 replicas: $(kubectl -n app get deploy demo -o jsonpath='{.spec.replicas}')"
helm history demo -n app | tail -3

echo "=== revision Secret들 ==="
kubectl -n app get secret -l owner=helm --no-headers | awk '{print "  "$1}'
```

✅ revision마다 Secret이 하나씩. `--history-max`(기본 10)를 넘으면 오래된 것이 정리됩니다 — **큰 차트를 자주 배포하면 Secret 크기·etcd 부담**을 의식하세요(09의 etcd 지식).

## Step 8. pending 상태 복구 — 실무 급소

```bash
cat <<'EOF'
증상: "another operation (install/upgrade/rollback) is in progress"
원인: 이전 명령이 중단(Ctrl-C·CI 타임아웃)되어 릴리스가 pending-* 상태에 고착
진단: helm history <release> -n <ns>   → status가 pending-upgrade 등
해결:
  ① helm rollback <release> <last-good-revision> -n <ns>
  ② 그래도 안 되면 해당 revision Secret 삭제 (신중히):
     kubectl -n <ns> delete secret sh.helm.release.v1.<release>.v<N>
예방: CI에서 --wait --timeout 명시, 중단 시 자동 rollback 스텝
EOF
```

## 정리

lab-02에서 훅과 GitOps 충돌을 다룹니다. 유지.
