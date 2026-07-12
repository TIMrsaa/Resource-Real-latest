# Lab 01 — CRD 설계 풀코스

## Step 1. CRD 등록 (theory의 Website CRD)

theory.md의 CRD YAML을 `manifests/website-crd.yaml`로 저장돼 있다고 가정하거나 직접 작성해 적용:

```bash
kubectl apply -f manifests/website-crd.yaml
kubectl get crd websites.platform.example.com
kubectl api-resources | grep website
```

예상 출력:
```
websites   ws   platform.example.com/v1   true   Website     ← 새 리소스 종류 탄생!
```

## Step 2. API 서버가 공짜로 주는 것들 확인

```bash
# ① kubectl 통합 + explain (스키마가 곧 문서)
kubectl explain website.spec
kubectl explain website.spec.replicas

# ② REST 엔드포인트
kubectl get --raw /apis/platform.example.com/v1 | python3 -m json.tool | head -15

# ③ 스키마 검증 — 일부러 위반
cat <<'EOF' | kubectl apply -f -
apiVersion: platform.example.com/v1
kind: Website
metadata: { name: bad }
spec: { image: "nginx", replicas: 99 }
EOF
```

예상 출력 (검증 거부 2건):
```
The Website "bad" is invalid:
* spec.image: Invalid value: "nginx": ... should match '^.+:.+$'
* spec.replicas: Invalid value: 99: ... should be less than or equal to 10
```

✅ 코드 한 줄 없이 — 등록한 스키마만으로 — 검증/문서/API가 작동합니다.

## Step 3. 정상 객체 + 출력 컬럼

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: platform.example.com/v1
kind: Website
metadata: { name: blog }
spec: { image: "public.ecr.aws/nginx/nginx:1.27", replicas: 3, domain: "blog.example.com" }
EOF
kubectl get ws
```

예상 출력:
```
NAME   READY   PHASE
blog                    ← status가 비어 컬럼도 빔 (컨트롤러가 없으니까!)
```

✅ **CRD만으로는 아무 일도 일어나지 않습니다** — spec은 저장됐지만 그걸 실현할 컨트롤러(모듈 30)가 없습니다. "명사는 등록됐고 동사가 없다"의 상태.

## Step 4. status 서브리소스 체험 — 컨트롤러 역할 흉내

```bash
# 일반 apply로 status를 넣으면? — 무시됩니다 (서브리소스 분리 덕)
kubectl patch ws blog --type=merge -p '{"status":{"readyReplicas":3,"phase":"Ready"}}'
kubectl get ws blog -o jsonpath='{.status}'; echo   # → (비어있음!)

# /status 엔드포인트로 직접 (컨트롤러가 하는 방식)
kubectl patch ws blog --subresource=status --type=merge \
  -p '{"status":{"readyReplicas":3,"phase":"Ready"}}'
kubectl get ws
```

예상 출력:
```
NAME   READY   PHASE
blog   3       Ready      ← 이제 컬럼이 찹니다
```

✅ spec 채널과 status 채널이 정말 분리되어 있습니다 — RBAC로 "사용자는 status에 못 쓰게" 만들 수 있는 구조적 토대.

## Step 5. scale 서브리소스 — 표준 도구와의 호환

```bash
kubectl scale ws blog --replicas=5      # kubectl scale이 그냥 됩니다!
kubectl get ws blog -o jsonpath='{.spec.replicas}'; echo   # → 5
```

✅ scale 서브리소스 선언 덕에 **HPA까지 이 CRD를 대상으로 동작 가능**합니다 — 잘 설계된 CRD는 기존 생태계에 끼워집니다.

## Step 6. CEL 검증 추가 — 교차 필드 규칙

CRD의 schema에 x-kubernetes-validations를 추가해 재적용:

```bash
kubectl patch crd websites.platform.example.com --type=json -p='[
 {"op":"add",
  "path":"/spec/versions/0/schema/openAPIV3Schema/properties/spec/x-kubernetes-validations",
  "value":[{"rule":"!has(self.domain) || self.replicas >= 2",
            "message":"domain이 있으면(외부 노출) replicas는 2 이상이어야 한다"}]}]'

# 위반 시도: 도메인 있는데 replicas 1
kubectl patch ws blog --type=merge -p '{"spec":{"replicas":1}}'
```

예상 출력:
```
The Website "blog" is invalid: spec: Invalid value: ... domain이 있으면(외부 노출) replicas는 2 이상이어야 합니다
```

✅ "외부 노출 서비스는 단일 replica 금지" — 모듈 13 pitfall의 교훈이 **API 설계 자체에 내장**됐습니다. 스키마(필드 단위) + CEL(교차 필드)의 2단 검증 체계.

## 정리

blog/CRD는 lab-02에서 계속 사용.
