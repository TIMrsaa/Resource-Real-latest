# Lab 02 — 복제, 프록시 캐시(rate limit 해법), OCI 아티팩트

레지스트리가 rate limit 문제를 풀고, 이미지 아닌 것도 저장하는 것을 확인합니다.

전제: lab-01의 클러스터(kind: harbor).

## Step 1. 프록시 캐시 — cicd 25의 rate limit 해법

```bash
cat <<'EOF'
=== 프록시 캐시 (theory §4, cicd 25 카드 8) ===
문제 (cicd 25): Docker Hub 익명 rate limit (429 Too Many Requests)
  러너들이 공유 IP로 Docker Hub를 치면 한도 초과
  (self-hosted 러너가 NAT 뒤에 있으면 특히)

Harbor 프록시 캐시:
  1. Harbor에 Docker Hub 프록시 프로젝트 생성 (proxy-cache)
  2. 클러스터가 harbor.local/proxy-cache/library/nginx 를 pull
  3. Harbor가 처음엔 Docker Hub에서 받아 캐시, 이후는 캐시에서
  → Docker Hub를 직접 안 침 → rate limit 회피

효과:
  - rate limit 해결 (외부 의존을 내부 레지스트리로 흡수)
  - 지연 감소 (로컬 캐시)
  - 오프라인·에어갭 (외부 안 나가도 됨)
  - 인증 pull로 한도 상향 (Harbor가 인증된 계정으로 원본 접근)

★ cicd 25의 "레지스트리 rate limit" 진단 카드의 근본 대응
EOF
```

## Step 2. 복제 — 멀티 레지스트리

```bash
cat <<'EOF'
=== 복제(replication) (theory §4) ===
Harbor ↔ 다른 레지스트리:
  대상: 다른 Harbor, ECR, GCR, Docker Hub, ACR
  방식: push-based(우리가 밀기) / pull-based(우리가 당기기)
  필터: 태그·라벨·리소스 (prod-* 만 복제 등)
  트리거: 수동 / 스케줄 / 이벤트(push 시 즉시)

용도:
  재해 대비: 다중 지역에 이미지 사본 (05·09의 백업 관점)
  지연 감소: 엣지 지역에 가까운 레지스트리
  마이그레이션: 레지스트리 이전
  멀티 클라우드: AWS ECR ↔ Harbor ↔ GCP GCR

★ 이미지도 데이터 (05의 데이터 중력):
  레지스트리 이전·복제가 곧 데이터 이동
  Harbor는 스테이트풀 → 05·09의 백업·복구 적용
EOF
```

## Step 3. OCI 아티팩트 — 이미지 아닌 것도

```bash
cat <<'EOF'
=== OCI 아티팩트 (theory §5, cicd 21·15) ===
같은 레지스트리에 저장:

① 컨테이너 이미지 (전통)
   docker push harbor.local/team/app:v1

② Helm 차트 (15 — OCI 차트)
   helm push mychart-1.0.tgz oci://harbor.local/team/charts
   → ArgoCD(16)·Flux(17)가 OCI 차트를 소스로

③ SBOM (21 — 이미지 성분표)
   cosign attach sbom --sbom sbom.json harbor.local/team/app:v1
   → 이미지 옆에 첨부 (신규 CVE 소급 조회)

④ 서명·attestation (21 — provenance)
   cosign sign / cosign attest
   → 이미지 옆에 (Harbor가 표시·연계)

⑤ WASM(03)·AI 모델·파일 번들

→ "레지스트리 = OCI 아티팩트 저장소"
  distribution-spec(03)의 확장이 이 모든 것을 가능하게
  Harbor가 타입별 관리·서명·스캔 연계
EOF
```

## Step 4. cicd 21·15가 여기서 통합됨

```bash
cat <<'EOF'
=== 흩어진 공급망 산출물이 한 레지스트리에 (theory §5) ===
cicd 21에서 별도로 배운 것들:
  이미지 서명(cosign) → Harbor에 저장·검증
  SBOM(syft) → OCI 아티팩트로 이미지에 첨부
  provenance(19의 --provenance) → attestation 아티팩트

cicd 15에서:
  Helm 차트 OCI → 같은 레지스트리에

→ 배포에 필요한 모든 것(이미지·차트·SBOM·서명)이 한 레지스트리에
  하나의 다이제스트로 이미지+SBOM+서명이 연결
  (image index가 이미지+attestation manifest를 담습니다 — cicd 19)

실무 의미:
  배포 = 레지스트리에서 이미지 + 그 서명 검증 + SBOM 조회
  전부 한 곳에서 (관문의 완성)
EOF
```

## Step 5. 신뢰 경계로서의 레지스트리 — 방어 종합

```bash
cat <<'EOF'
=== 레지스트리 침해 방어 (theory §6, cicd 21) ===
공급망 공격 지도(21)의 "아티팩트 저장" 고리:
  레지스트리 침해 = 모든 배포 오염

Harbor의 방어 계층:
  RBAC: 프로젝트별 역할 (누가 push/pull/삭제)
  로봇 계정: CI용 제한 자격증명 (사람과 분리 — 22)
  불변 태그: 태그 덮어쓰기 금지 (04·21의 태그 변경 방지)
  스캔 게이트: 취약 이미지 차단
  서명 검증: 미서명 차단
  감사 로그: 누가 무엇을 (24)
  복제: 재해 대비 (한 레지스트리 장애에 대비)

★ 관리형(ECR·GHCR)이든 Harbor든 동일한 관점:
  레지스트리에서 스캔·서명·접근통제·감사를 하는 것이
  공급망 방어의 중심 고리 (07의 신뢰 경계)
EOF
```

## Step 6. 도입 판단

```bash
cat <<'EOF'
=== Harbor 자체 운영 vs 관리형 (theory §7) ===
관리형 (ECR·GCR·GHCR·ACR):
  대부분의 클라우드 사용자 — 운영 부담 0, IAM 통합, 스캔·서명 제공

Harbor 자체 운영:
  온프레·에어갭 (관리형 없음)
  멀티 클라우드 통합 레지스트리 (벤더 독립)
  세밀한 정책·복제 제어
  → 05·09의 자체 운영 판단 프레임:
    Harbor도 스테이트풀(이미지=데이터) → 스토리지·백업·복구·운영 역량
    "새벽 3시에 레지스트리를 고칠 사람"이 있는가

★ 어느 쪽이든 배워야 할 것:
  "레지스트리에서 무엇을 스캔·서명·통제하나"의 관점
  (Harbor를 안 써도 ECR의 스캔·GHCR의 서명에 같은 관점 적용)
EOF
```

## Step 7. 산출물

```markdown
# Harbor 종합 카드
## 레지스트리를 관문으로
- 스캔(21)·서명(21)·정책·복제·RBAC를 레지스트리에 통합
- 모든 이미지가 통과 = 공급망 관문 = 신뢰 경계(07)

## 핵심 기능
- 프록시 캐시: Docker Hub rate limit 해법(cicd 25)
- 복제: 재해 대비·멀티클라우드 (05·09의 데이터)
- OCI 아티팩트: 이미지+Helm 차트(15)+SBOM(21)+서명 한 곳에
- 방어: RBAC·로봇계정(22)·불변태그(04)·스캔·서명·감사(24)

## 판단
- 관리형(ECR/GHCR) vs 자체(Harbor: 온프레·멀티클라우드·스테이트풀)
- 어느 쪽이든 "레지스트리에서 스캔·서명·통제" 관점은 동일
```

## 정리

```bash
bash cleanup.sh
```
