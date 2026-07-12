# Lab 02 — 부트스트랩 신뢰와 신원의 통일

"최초 신원을 어떻게"의 답을 정리하고, SPIFFE가 24·21·07의 신원을 어떻게 통일하는지 봅니다.

전제: lab-01의 클러스터(kind: spire).

## Step 1. 부트스트랩 문제 — turtles all the way down

```bash
cat <<'EOF'
=== 신원의 근본 문제 (guide, theory §4) ===

워크로드에게 신원을 주려면:
  "네가 진짜 그 워크로드임"을 확인해야 합니다
확인하려면:
  뭔가 검증 가능한 것이 있어야 합니다
그 뭔가의 신뢰는:
  또 어디서 오나요?
→ 무한 후퇴 (turtles all the way down)

전통적 답 (실패):
  부트스트랩 시크릿을 미리 심습니다
  → 그 시크릿을 어떻게 안전하게 전달? (또 같은 문제)
  → 그리고 유출되면 신원 도용
EOF
```

## Step 2. SPIRE의 답 — 플랫폼에 신뢰를 뿌리내리기

```bash
cat <<'EOF'
=== SPIRE의 부트스트랩 (theory §4) ===

신뢰의 사슬을 '플랫폼의 기존 신뢰'에 뿌리:

  노드 어테스테이션:
    AWS: 노드가 EC2 Instance Identity Document 제시
         → AWS가 서명한 것 → AWS를 신뢰하면 노드를 신뢰
    K8s: 노드가 Projected SA Token 제시
         → API 서버가 검증 → K8s를 신뢰하면 노드를 신뢰

  → 신뢰의 바닥 = "클라우드가 자기 인스턴스를 아는 것"
                  "K8s가 자기 Pod의 SA를 아는 것"
  → 이미 존재하는 신뢰를 활용 (새 시크릿 안 만듦)

★ 07의 OIDC와 정확히 같은 통찰:
  GitHub이 워크플로를 아는 것(OIDC) = 부트스트랩 시크릿 없는 신원
  AWS가 인스턴스를 아는 것(IID) = SPIRE 노드 어테스테이션
  → "플랫폼이 이미 아는 것"이 신뢰의 바닥
  → turtles의 맨 아래 거북이 = 플랫폼
EOF
```

## Step 3. IP·시크릿과의 최종 대비

```bash
cat <<'EOF'
=== 세 가지 신원 방법 (theory §1) ===
| 방법 | 재생성 | 유출 시 | 위조 |
|------|--------|---------|------|
| IP 주소 | 바뀜(K8s) | — | 스푸핑 가능 |
| 공유 시크릿 | 유지 | 신원 도용(누구나) | 시크릿 알면 |
| SPIFFE SVID | 불변(신원) | 그 워크로드 하나 | 불가(어테스테이션) |

SPIFFE의 우위:
  - Pod 재생성·IP 변경에 신원 불변 (22의 Cilium identity와 같은 문제의식)
  - 공유 시크릿이 아니라 각자의 검증 가능한 인증서
    → 하나 유출돼도 그 워크로드만 (blast radius 최소)
  - 어테스테이션이라 위조 불가 (커널·플랫폼이 증명)
  - 짧은 수명 + 자동 갱신 (07·22의 단명 원리)
EOF
```

## Step 4. 신원의 통일 — 흩어진 조각들이 SPIFFE로

```bash
cat <<'EOF'
=== 07의 신원 축이 SPIFFE로 수렴 (theory §6) ===

지금까지 만난 "신원"들:
  cicd 07 OIDC:    GitHub이 워크플로를 증언 (CI 신원)
  cicd 21 keyless: OIDC 신원으로 서명 (서명 신원)
  eks IRSA:        Pod에 클라우드 신원
  19 cert-manager: 인증서라는 물건
  24 Istio mTLS:   서비스 간 SPIFFE ID  ← 이미 SPIFFE!
  22 Cilium identity: 라벨 기반 신원 (다른 구현)

SPIFFE의 비전 (통일):
  Istio(24): mTLS 신원 = SPIFFE ID (istiod가 SPIRE 역할 또는 통합)
  Envoy(23): SDS로 SPIFFE SVID 수신
  cert-manager(19): csi-driver-spiffe로 SVID를 인증서로
  → 서비스 메시·서명·클라우드 접근이 같은 "검증 가능한 워크로드 신원" 공유

★ "공유 시크릿의 종말":
  비밀번호(공유 시크릿) → 신원 증명(검증 가능, 각자의 것)
  이것이 커리큘럼 전체가 반복한 주제의 종착점
EOF
```

## Step 5. 페더레이션 — 신뢰 영역 간

```bash
cat <<'EOF'
=== 멀티 클러스터·멀티 조직 (theory §6) ===
페더레이션: 다른 trust domain 간 신뢰
  spiffe://cluster-a.example.org  ↔  spiffe://cluster-b.example.org
  → Trust Bundle 교환 → 서로의 SVID 검증 가능

용도:
  - 멀티 클러스터 (16의 멀티클러스터에서 워크로드 신원)
  - 멀티 클라우드 (AWS 워크로드 ↔ GCP 워크로드)
  - 조직 간 (파트너사 서비스와 mTLS)

→ IP·시크릿으로는 불가능했던 "경계를 넘는 워크로드 신원"
EOF
```

## Step 6. 도입 판단 — SPIFFE/SPIRE의 자리

```bash
cat <<'EOF'
=== 언제 SPIRE를 직접 운영하나 ===
많은 경우 SPIFFE를 '간접적으로' 씁니다:
  Istio(24) 쓰면 → istiod가 SPIFFE ID 발급 (SPIRE 직접 운영 안 함)
  → 대부분 조직은 메시를 통해 SPIFFE를 이미 씁니다

SPIRE를 직접 운영하는 경우:
  - 메시 밖 워크로드에도 통일된 신원 (VM, 레거시, 다양한 플랫폼)
  - 멀티 클라우드·멀티 클러스터 페더레이션
  - 세밀한 어테스테이션 정책
  - 신원을 메시에 종속시키지 않으려는 플랫폼 팀

대가:
  SPIRE Server·Agent 운영 (또 하나의 중요 인프라)
  Server가 신뢰의 루트 → 그 가용성·보안이 전체 신원의 SPOF
  어테스테이션 설정의 복잡도

★ "신원"은 보안의 척추(07) → SPIRE는 그 척추를 직접 세우는 것
  대부분은 메시(24)를 통해 간접적으로, 필요하면 직접
EOF
```

## Step 7. 산출물 — 07 신원 축 종합

```markdown
# SPIFFE/SPIRE 종합 (07 신원 축의 완성)
## 부트스트랩
- turtles 문제: 신원을 주려면 확인, 확인하려면 신뢰...
- 답: 플랫폼의 기존 신뢰에 뿌리 (클라우드가 인스턴스를, K8s가 SA를 앎)
- = 07의 OIDC 통찰 (부트스트랩 시크릿 없는 신원)

## 우위
- IP(바뀜·스푸핑)·시크릿(유출·도용)보다 우월
- 재생성 불변, blast radius 최소, 위조 불가(어테스테이션), 단명

## 통일
- Istio·Envoy·cert-manager·OIDC가 SPIFFE로 수렴
- "공유 시크릿의 종말" — 커리큘럼 신원 주제의 종착점

## 도입
- 대부분 메시(24)를 통해 간접 사용
- 직접 운영: 메시 밖 통일 신원, 페더레이션, 플랫폼 팀
- Server = 신원의 SPOF (가용성·보안 핵심)
```

## 정리

```bash
bash cleanup.sh
```
