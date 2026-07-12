# Lab 01 — rego 사고법: 선언적 정책 작성과 테스트

rego의 "위반은 조건일 때 존재한다"라는 사고 전환을 손으로 익힙니다. cicd 24에서 conftest를 썼다면, 여기서 rego를 제대로 배웁니다.

전제: opa CLI(`brew install opa` 또는 릴리스 바이너리), python3.

## Step 1. 첫 정책 — allow/deny

```bash
mkdir -p ~/cncf-lab/opa && cd ~/cncf-lab/opa

cat > authz.rego <<'EOF'
package authz

# 기본은 거부 (default deny)
default allow := false

# allow는 이 조건이 참일 때 true
allow {
    input.user == "admin"
}

allow {
    input.user == "alice"
    input.action == "read"
}
EOF

echo "=== admin은 무엇이든 허용 ==="
echo '{"user":"admin","action":"write"}' | opa eval -d authz.rego -I "data.authz.allow" -f raw

echo "=== alice는 read만 ==="
echo '{"user":"alice","action":"read"}' | opa eval -d authz.rego -I "data.authz.allow" -f raw
echo '{"user":"alice","action":"write"}' | opa eval -d authz.rego -I "data.authz.allow" -f raw
```

예상: admin/write → true, alice/read → true, alice/write → false. ✅ **allow는 여러 규칙 중 하나라도 성립하면 참**(theory §2) — "이런 경우 허용"을 나열하는 선언적 사고.

## Step 2. 사고 전환 — 명령형 vs 선언적

```bash
cat <<'EOF'
=== 같은 정책, 두 사고 (theory §2) ===

명령형(Python) — "순회하며 찾아라":
  def check(user, action):
      if user == "admin": return True
      if user == "alice" and action == "read": return True
      return False

rego(선언적) — "허용은 이런 조건들일 때":
  allow { input.user == "admin" }
  allow { input.user == "alice"; input.action == "read" }

전환: "어떻게 계산하나" → "무엇이 참인가"
  OPA가 조건 평가를 대신합니다 (우리는 조건만 선언)
EOF
```

## Step 3. 위반 수집 — 부분 규칙(set)

```bash
cat > k8s.rego <<'EOF'
package kubernetes.admission

# deny[msg] = "msg를 만족하는 조건" — 여러 위반이 집합에 모입니다
deny[msg] {
    input.kind == "Pod"
    container := input.spec.containers[_]        # _ = 모든 컨테이너 순회
    not container.securityContext.runAsNonRoot
    msg := sprintf("container '%s' must run as non-root", [container.name])
}

deny[msg] {
    input.kind == "Pod"
    container := input.spec.containers[_]
    endswith(container.image, ":latest")
    msg := sprintf("container '%s' uses :latest tag", [container.name])
}
EOF

# 위반 여러 개인 입력
cat > bad-pod.json <<'EOF'
{
  "kind": "Pod",
  "spec": {
    "containers": [
      {"name": "app", "image": "nginx:latest"},
      {"name": "sidecar", "image": "proxy:1.2", "securityContext": {"runAsNonRoot": true}}
    ]
  }
}
EOF

echo "=== 위반 수집 ==="
opa eval -d k8s.rego -i bad-pod.json "data.kubernetes.admission.deny" -f pretty
```

예상: app의 non-root 위반 + app의 latest 위반 = 2개(sidecar는 통과). ✅ **`[_]`가 모든 컨테이너를 순회하고, 규칙이 성립할 때마다 집합에 추가**(theory §2) — 명령형 루프 없이 모든 위반이 모입니다.

## Step 4. macro와 데이터 — 재사용

```bash
cat > advanced.rego <<'EOF'
package kubernetes.admission

# macro: 재사용 조건
is_pod { input.kind == "Pod" }

# data 참조: 배경 데이터(허용 레지스트리)
deny[msg] {
    is_pod
    container := input.spec.containers[_]
    not allowed_registry(container.image)
    msg := sprintf("image '%s' from untrusted registry", [container.image])
}

allowed_registry(image) {
    registry := data.trusted_registries[_]
    startswith(image, registry)
}
EOF

cat > data.json <<'EOF'
{ "trusted_registries": ["ghcr.io/myorg/", "registry.internal/"] }
EOF

cat > pod.json <<'EOF'
{ "kind": "Pod", "spec": { "containers": [
  {"name": "a", "image": "ghcr.io/myorg/app:v1"},
  {"name": "b", "image": "docker.io/random:latest"}
]}}
EOF

echo "=== data(신뢰 레지스트리)를 참조하는 정책 ==="
opa eval -d advanced.rego -d data.json -i pod.json "data.kubernetes.admission.deny" -f pretty
```

예상: b(docker.io)만 위반. ✅ **input(질의) + data(배경) + rego(규칙)**의 삼각(theory §1) — 정책 로직과 데이터(허용 목록)를 분리.

## Step 5. 정책 테스트 — cicd 24의 규율

```bash
cat > k8s_test.rego <<'EOF'
package kubernetes.admission

test_deny_root {
    deny[_] with input as {
        "kind": "Pod",
        "spec": {"containers": [{"name": "x", "image": "a:1.0"}]}
    }
}

test_allow_nonroot_pinned {
    count(deny) == 0 with input as {
        "kind": "Pod",
        "spec": {"containers": [{"name": "x", "image": "a:1.0",
                 "securityContext": {"runAsNonRoot": true}}]}
    }
}
EOF

opa test . -v 2>&1 | tail -6
```

예상: 테스트 통과. ✅ **정책도 테스트**(21·24) — 부정 테스트("무엇이 거부되는가")로 정책의 정확성을 검증.

## Step 6. rego playground 안내

```bash
cat <<'EOF'
연습 도구:
  https://play.openpolicyagent.org  (브라우저에서 rego 실험)
  opa eval -d policy.rego -i input.json "data.pkg.rule" -f pretty
  opa test .   (단위 테스트)
  opa fmt      (포맷)

rego 학습 팁:
  1. default로 기본값 (default allow := false)
  2. 규칙 본문의 모든 조건이 참 → 규칙 성립 (AND)
  3. 같은 이름 규칙 여러 개 → OR (하나라도 성립)
  4. [_]로 배열 순회, some x로 변수 바인딩
  5. not으로 부정, data로 배경 데이터
EOF
```

## Step 7. 산출물

```markdown
# rego 사고법 카드
- 선언적: "위반은 이 조건일 때 존재한다" (명령형 순회 아님)
- allow/deny: 여러 규칙 = OR, 본문 조건들 = AND
- default: 기본값 (default allow := false)
- [_]: 배열 순회 → 규칙 성립마다 집합에 수집
- input(질의) + data(배경) + rego(규칙) = 결정
- 테스트: opa test (부정 테스트로 검증 — 21·24)
```

## 정리

lab-02에서 Gatekeeper와 다영역을 다룹니다. 파일 유지.
