# Lab 01 — 레지스트리 + 보안: 프로젝트, 스캔, 정책

Harbor를 설치하고, 레지스트리가 어떻게 스캔·정책으로 공급망 관문이 되는지 확인합니다.

전제: kind, kubectl, helm. Harbor는 무거우므로 리소스 여유 필요(또는 개념 중심).

## Step 1. 클러스터와 Harbor

```bash
kind create cluster --name harbor -q

helm repo add harbor https://helm.goharbor.io >/dev/null 2>&1
helm install harbor harbor/harbor -n harbor --create-namespace \
  --set expose.type=nodePort \
  --set expose.tls.enabled=false \
  --set externalURL=http://harbor.local \
  --set persistence.enabled=false \
  --set trivy.enabled=true >/dev/null 2>&1 || \
  echo "(Harbor는 무겁습니다 — kubectl -n harbor get pods 로 진행 확인, 리소스 부족 시 개념 중심)"

sleep 30
kubectl -n harbor get pods 2>/dev/null | head -10
```

## Step 2. 컴포넌트 지도

```bash
echo "=== Harbor 컴포넌트 (theory §1) ==="
kubectl -n harbor get deploy,statefulset 2>/dev/null | grep harbor | head -10

cat <<'EOF'
역할:
  core        API·인증·권한·정책 (두뇌)
  registry    실제 이미지 저장 (distribution — OCI)
  jobservice  비동기 작업 (스캔·복제·GC)
  trivy       취약점 스캐너 (내장)
  database    메타데이터 / redis 캐시 / portal UI
EOF
```

## Step 3. 프로젝트 모델 — 정책·RBAC 경계

```bash
cat <<'EOF'
=== 프로젝트 = 정책·RBAC 경계 (theory §1) ===
프로젝트 생성 (UI 또는 API):
  이름: myteam
  접근 수준: private
  스캔 정책: "push 시 자동 스캔"
  CVE 심각도 차단: "Critical 있으면 pull 차단"
  서명 정책: "cosign 서명된 것만"
  쿼터: 10GB
  불변 태그: "prod-* 태그는 덮어쓰기 금지" (04)

RBAC 역할:
  ProjectAdmin, Maintainer, Developer, Guest, Limited Guest
  → 24의 멀티팀 거버넌스를 레지스트리에
  로봇 계정: CI용 제한된 자격증명 (사람과 분리)
EOF
```

## Step 4. 취약점 스캔 — push 시 자동 (cicd 21)

```bash
cat <<'EOF'
=== 스캔 게이트 (theory §2, cicd 21) ===
1. 이미지 push → Harbor가 Trivy로 자동 스캔
2. 레이어의 패키지를 CVE DB와 대조
   → Critical: 3, High: 12, Medium: 8, Low: 20 + CVE 목록

3. 배포 차단 정책:
   프로젝트 설정 "Prevent vulnerable images from running"
   심각도 임계: Critical
   → Critical 취약점 있는 이미지는 pull 차단
   → 취약한 이미지가 프로덕션에 못 나감 (레지스트리 게이트)

cicd 21과 다층:
  21: CI에서 Trivy 스캔 게이트 (빌드 시점)
  34: 레지스트리에서 스캔 차단 (저장 시점)
  → 이중 방어 (빌드 우회 경로도 레지스트리에서 막힘)

★ 신규 CVE 대응:
  Harbor가 이미 저장된 이미지를 재스캔 (스케줄)
  → "어제 안전했던 이미지가 오늘 Critical" 발견
  → 21의 SBOM 소급 조회의 레지스트리판
EOF
```

## Step 5. 서명 — 미서명 차단 (cicd 21)

```bash
cat <<'EOF'
=== 서명 통합 (theory §3, cicd 21) ===
cosign 서명을 Harbor가 저장·표시:
  cosign sign harbor.local/myteam/app@sha256:...
  → 서명이 이미지 옆 OCI 아티팩트로 저장

프로젝트 정책 "서명된 이미지만 pull":
  미서명 이미지 → pull 차단 (레지스트리 레벨)

cicd 21의 admission과 다층:
  21: Kyverno가 admission에서 서명 검증 (배포 시점)
  34: Harbor가 pull에서 서명 확인 (전송 시점)
  32: Kyverno verifyImages (배포 시점)
  → 07의 시간선 여러 층에 서명 검증 (다층 방어)
EOF
```

## Step 6. 불변 태그 — 태그 변경 방지 (cicd 04·21)

```bash
cat <<'EOF'
=== 불변 태그 (theory §6, cicd 04) ===
문제: tj-actions(21)·태그 변경 공격 — latest·v1이 다른 이미지를 가리키게
Harbor 정책 "Tag Immutability":
  prod-* 태그는 한 번 push되면 덮어쓰기 불가
  → 태그 변경 공격 차단 (04의 다이제스트 규율을 레지스트리 정책으로)

+ 로봇 계정:
  CI가 push할 때 사람 계정이 아닌 제한된 로봇 계정
  → 자격증명 유출 시 blast radius 최소 (22)
EOF
```

## Step 7. 산출물

```markdown
# Harbor 보안 관문 카드
- 프로젝트: 정책·RBAC 경계 (24의 거버넌스를 레지스트리에)
- 스캔(Trivy): push 시 자동 → Critical이면 pull 차단 (21과 다층)
- 서명(cosign): 미서명 pull 차단 (21 admission·32와 다층)
- 불변 태그: 태그 변경 공격 방지 (04·21)
- 로봇 계정: CI용 제한 자격증명 (22)
- 신규 CVE: 저장된 이미지 재스캔 (21의 소급)
- 레지스트리 = 모든 이미지가 통과하는 공급망 관문
```

## 정리

lab-02에서 복제·프록시·OCI 아티팩트를 다룹니다. 유지.
