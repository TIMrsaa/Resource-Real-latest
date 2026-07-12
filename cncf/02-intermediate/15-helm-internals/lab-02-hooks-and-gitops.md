# Lab 02 — 훅의 실체와 위험, 그리고 GitOps와의 긴장

훅으로 순서를 강제하고 그 함정을 밟은 뒤, "릴리스가 진실"과 "Git이 진실"의 충돌을 실험으로 확인합니다.

전제: lab-01의 클러스터(kind: helm)와 차트(~/cncf-lab/helm/demo).

## Step 1. pre-upgrade 훅 — DB 마이그레이션 흉내

```bash
cd ~/cncf-lab/helm/demo
cat > templates/migrate-hook.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "demo.fullname" . }}-migrate
  annotations:
    "helm.sh/hook": pre-upgrade,pre-install
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: busybox
          command: ["sh","-c","echo 'running migration v{{ .Values.migrationVersion | default 1 }}'; sleep 5; echo done"]
EOF

helm upgrade demo . -n app --set migrationVersion=2 --wait --timeout 2m 2>&1 | tail -3
kubectl -n app get jobs
kubectl -n app logs job/demo-migrate 2>/dev/null | tail -2 || echo "(hook-succeeded 정책으로 이미 삭제됨)"
```

✅ 훅 Job이 **앱 업그레이드 전에** 실행되고, 성공 후 삭제됐습니다(delete-policy). cicd 14의 sync wave(마이그레이션 → 앱)와 같은 문제를 Helm은 훅으로 풉니다.

## Step 2. 훅의 함정 ① — 실패 시 부작용은 롤백되지 않습니다

```bash
cat > templates/migrate-hook.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "demo.fullname" . }}-migrate
  annotations:
    "helm.sh/hook": pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: busybox
          command: ["sh","-c","echo 'STEP 1: ALTER TABLE ... (부작용 발생!)'; sleep 2; echo 'STEP 2: 실패'; exit 1"]
EOF

helm upgrade demo . -n app --set replicaCount=4 --wait --timeout 90s 2>&1 | tail -3
echo "---"
kubectl -n app logs job/demo-migrate 2>/dev/null | tail -3
echo "---"
echo "앱의 replicas: $(kubectl -n app get deploy demo -o jsonpath='{.spec.replicas}')  ← 업그레이드는 실패(4 아님)"
helm history demo -n app | tail -2
```

예상: 훅 실패 → 업그레이드 실패(앱은 안 바뀜). **그러나 STEP 1의 "ALTER TABLE"은 이미 실행됐습니다.** ✅ theory §5의 위험: 훅은 순서를 강제하지만 **부작용의 롤백은 아무도 안 해줍니다** — 마이그레이션은 반드시 멱등·전진 호환(expand-contract, cicd 11)으로 설계해야 합니다.

```bash
kubectl -n app delete job demo-migrate --ignore-not-found >/dev/null
```

## Step 3. 훅의 함정 ② — 릴리스 밖 리소스

```bash
cat > templates/migrate-hook.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "demo.fullname" . }}-hookcm
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    # 🐛 hook-delete-policy 없음!
data: { note: "이 리소스는 릴리스의 일부가 아니다" }
EOF
helm upgrade demo . -n app >/dev/null 2>&1
kubectl -n app get cm demo-hookcm >/dev/null 2>&1 && echo "훅 ConfigMap 생성됨"

# 릴리스 매니페스트에 이것이 있는가요?
kubectl -n app get secret -l owner=helm,version=$(helm history demo -n app --output json | python3 -c "import json,sys; print(json.load(sys.stdin)[-1]['revision'])") \
  -o jsonpath='{.items[0].data.release}' 2>/dev/null | base64 -d | base64 -d | gunzip | \
  python3 -c "import json,sys; print('릴리스 매니페스트에 hookcm 포함?', 'hookcm' in json.load(sys.stdin)['manifest'])"

cat <<'EOF'
→ 훅 리소스는 릴리스 매니페스트에 없습니다 → helm uninstall 해도 남습니다(고아)
   반드시 hook-delete-policy 를 명시하세요:
     before-hook-creation : 다음 실행 전에 이전 것 삭제 (기본 권장)
     hook-succeeded       : 성공하면 삭제
     hook-failed          : 실패하면 삭제 (디버깅하려면 빼라)
EOF
rm templates/migrate-hook.yaml
```

## Step 4. GitOps 충돌 — 두 진실의 대결

```bash
# ArgoCD 방식 흉내: helm template 으로 렌더링만 하고 kubectl apply
helm template demo . -n app --set replicaCount=6 > /tmp/rendered.yaml
kubectl -n app apply -f /tmp/rendered.yaml >/dev/null
echo "template+apply 후 replicas: $(kubectl -n app get deploy demo -o jsonpath='{.spec.replicas}')"

echo ""
echo "=== Helm은 이 변경을 알고 있는가요? ==="
helm get values demo -n app | head -5
echo "→ 릴리스의 values는 그대로입니다. 클러스터만 바뀌었습니다."
echo ""
echo "=== 이 상태에서 helm upgrade 하면? ==="
helm upgrade demo . -n app >/dev/null
sleep 3
echo "helm upgrade 후 replicas: $(kubectl -n app get deploy demo -o jsonpath='{.spec.replicas}')"
```

예상: helm이 자기 old(저장된 값)를 기준으로 판단하므로 되돌아갑니다 — **두 도구가 서로의 변경을 모릅니다**. ✅ 이것이 theory §6의 긴장: 릴리스 Secret과 Git이 각각 진실이라고 주장하면 진동합니다.

## Step 5. 세 가지 해법 비교

```bash
cat <<'EOF'
[A] ArgoCD 방식 — Helm을 '템플릿 엔진'으로만
    Git: Chart + values.yaml
    ArgoCD repo-server: helm template 실행 → 매니페스트 → 클러스터와 비교(diff)
    릴리스 Secret 없음. helm history/rollback 불가 (Git revert가 롤백)
    훅: ArgoCD의 sync hook(PreSync 등)으로 매핑 — 일부 helm 훅은 자동 변환됨
    ✅ 진실은 Git 하나. 진동 없음.

[B] Flux 방식 — HelmRelease CR
    Git: HelmRelease{chart, values}
    helm-controller: 실제 helm 릴리스를 생성·관리 (Secret 존재, history 유지)
    ✅ Helm의 상태 기계를 살리면서 선언은 Git에 (17에서 심화)

[C] CI 렌더 (rendered manifests)
    CI: helm template → 완성 YAML을 Git에 커밋
    ✅ PR diff가 정직 (차트 업그레이드로 사이드카가 추가되는 것이 보입니다 — 08 pitfalls)
    ❌ 저장소가 커지고 파이프라인 한 겹

★ 어느 쪽이든 금지: helm CLI와 GitOps 컨트롤러가 '같은 릴리스'를 동시에 관리
EOF
```

## Step 6. 실무 방어 세트

```bash
# ① values 스키마로 잘못된 입력 사전 차단
cat > values.schema.json <<'EOF'
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "properties": {
    "replicaCount": { "type": "integer", "minimum": 1, "maximum": 20 },
    "image": {
      "type": "object",
      "properties": { "tag": { "type": "string", "pattern": "^(?!latest$).+" } }
    }
  },
  "required": ["replicaCount"]
}
EOF
helm template demo . --set replicaCount=99 2>&1 | tail -2
echo "→ 스키마 위반이 렌더링 전에 잡힙니다 (latest 태그 금지도 — cicd 04)"

# ② 렌더링 결과에 정책 검사 (cicd 24)
helm template demo . > /tmp/out.yaml
echo "→ conftest test /tmp/out.yaml -p policy/  로 admission 이전에 게이트"

# ③ CRD 주의
echo ""
echo "crds/ 디렉터리: 설치 시에만 생성, upgrade/uninstall 시 건드리지 않음"
echo "  → CRD 버전 업그레이드는 별도 절차(수동 apply 또는 오퍼레이터)"
```

## Step 7. 산출물

```markdown
# Helm 운영 카드
- 릴리스 = Secret(sh.helm.release.v1.<name>.v<rev>) — 매니페스트 전문 보관
- upgrade = 3-way 병합(old/live/new) → 수동 변경의 생존 여부가 여기서 갈립니다
- HPA가 있으면 차트에서 replicas 제거 (필드 소유권 — cicd 14)
- 훅: delete-policy 필수, 부작용은 멱등·전진호환으로(cicd 11)
- pending-* 고착: helm rollback → 안 되면 revision Secret 정리
- GitOps: ArgoCD(템플릿만) / Flux(HelmRelease) / CI 렌더 — 셋 중 하나로 통일
- 방어: lint + --dry-run + values.schema.json + 렌더 결과 정책 검사
```

## 정리

```bash
bash cleanup.sh
```
