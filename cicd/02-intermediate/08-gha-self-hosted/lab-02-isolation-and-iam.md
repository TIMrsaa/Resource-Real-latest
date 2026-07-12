# Lab 02 — 오염을 실험하고, 러너의 IAM 경계를 긋습니다

self-hosted의 자유는 격리와 IAM을 우리 책임으로 만듭니다. 이 랩은 ephemeral이 왜 협상 불가인지 실험으로 보이고, 러너 Pod의 권한 경계를 설계합니다.

전제: lab-01의 ARC(arc-runners ns, eks-runners 스케일셋).

## Step 1. ephemeral이 격리하는 것 — 파일이 남지 않습니다

```bash
cd ~/ci-lab/arc
cat > .github/workflows/isolation.yml <<'EOF'
name: isolation-test
on: workflow_dispatch
jobs:
  # 잡 A: 파일과 "자격증명"을 남깁니다
  job-a:
    runs-on: eks-runners
    steps:
      - run: |
          echo "SECRET_FROM_A=leaked" > /tmp/creds.txt
          echo "job-a가 /tmp/creds.txt를 남겼다 on $(hostname)"

  # 잡 B: A의 흔적을 찾습니다
  job-b:
    runs-on: eks-runners
    needs: job-a
    steps:
      - run: |
          echo "job-b on $(hostname)"
          if [ -f /tmp/creds.txt ]; then
            echo "🚨 오염: $(cat /tmp/creds.txt)"
          else
            echo "✅ 격리됨: A의 파일이 없습니다 (다른 Pod입니다)"
          fi
EOF
git add -A && git commit -qm "test: isolation" && git push -q
gh workflow run isolation.yml && sleep 70
gh run view --log 2>/dev/null | grep -E "격리됨|오염|hostname|on eks" | head -4
```

예상: job-b는 `✅ 격리됨` — **A와 B는 다른 Pod**라 파일이 공유되지 않습니다. hostname도 다릅니다.

✅ 이것이 GitHub-hosted가 공짜로 주던 격리를 ephemeral 러너로 되찾은 것입니다. persistent 러너였다면 job-b가 `/tmp/creds.txt`를 읽었을 것입니다(theory §3).

## Step 2. persistent였다면? — 위험을 개념으로 확인

```markdown
# persistent 러너(재사용)에서 잡 B가 접근 가능한 A의 잔재
| 잔재 | 위험 |
|------|------|
| ~/.docker/config.json | 레지스트리 자격증명 |
| ~/.aws/credentials, 환경변수 | 이전 잡의 임시 자격증명 |
| 전역 설치 패키지 | "로컬에선 되는데 CI에서만" 재현 불가 버그 |
| 백그라운드 프로세스 | 다음 잡을 감시·조작 |
→ 다른 팀의 잡이 같은 러너에 오면 = 크로스 팀 자격증명 유출
→ 그래서 ARC 기본값은 ephemeral. persistent는 이 목록을 수용하겠다는 선언
```

## Step 3. 러너 Pod에 NetworkPolicy — VPC 스캔 차단

러너가 VPC 안에 있으므로(lab-01 Step 5), 오염되면 내부를 스캔할 수 있습니다. 기본 거부로 잠급니다(eks 18의 그 리소스):

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: runner-egress-lockdown
  namespace: arc-runners
spec:
  podSelector:
    matchLabels: { app.kubernetes.io/component: runner }
  policyTypes: [Egress]
  egress:
  - to: []                          # DNS
    ports: [{ protocol: UDP, port: 53 }, { protocol: TCP, port: 53 }]
  - to: []                          # HTTPS (GitHub, ECR, 패키지 레지스트리)
    ports: [{ protocol: TCP, port: 443 }]
    # ★ 내부 대역(10.0.0.0/8 등)으로의 임의 접근은 허용하지 않습니다
EOF
```

> 통합 테스트가 VPC 안 DB에 붙어야 한다면 — 그 특정 대상만 egress에 열어라(전체 개방이 아니라). "VPC 접근"이 이유였다면 접근 대상은 구체적일 것입니다.

## Step 4. IMDS 차단 확인 — eks 25의 핵심이 CI에도

러너 Pod가 노드 IMDS에 접근하면 노드 IAM 역할을 탈취할 수 있습니다:

```bash
cat > .github/workflows/imds.yml <<'EOF'
name: imds-check
on: workflow_dispatch
jobs:
  probe:
    runs-on: eks-runners
    steps:
      - name: IMDS 접근 시도 (막혀 있어야 합니다)
        run: |
          TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
            -H "X-aws-ec2-metadata-token-ttl-seconds: 60" --max-time 3 || echo "")
          if [ -z "$TOKEN" ]; then
            echo "✅ IMDS 차단됨 (hop limit=1 또는 NetworkPolicy)"
          else
            ROLE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
              http://169.254.169.254/latest/meta-data/iam/security-credentials/ --max-time 3)
            echo "🚨 노드 역할 노출: $ROLE"
          fi
EOF
git add -A && git commit -qm "test: imds" && git push -q
gh workflow run imds.yml && sleep 60
gh run view --log 2>/dev/null | grep -E "IMDS 차단|노드 역할 노출" | head -1
```

예상: 노드에 hop limit=1이 걸려 있으면(eks 25 실습) `✅ 차단됨`. 아니라면 이 실험이 **왜 그것이 필요한지**를 증명합니다 — CI 러너는 남의 코드가 실행될 수 있는 곳입니다.

## Step 5. 러너의 두 층 IAM — Pod Identity vs OIDC

러너 Pod 자신의 권한(①)과 워크플로가 assume하는 역할(②)을 분리합니다(theory §6).

```bash
# ① 러너 Pod 자신: 최소 (ECR pull, 로그) — Pod Identity (eks 09)
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
# (실습에선 개념 확인 — 실제 배선은 eks 09의 절차)
cat <<EOF
러너 Pod 역할 (Pod Identity):
  ✔ ecr:GetAuthorizationToken, ecr:BatchGetImage (이미지 pull)
  ✔ logs:PutLogEvents (러너 로그)
  ✘ 배포 권한 없음  ← 여기에 배포 권한을 주면 모든 워크플로가 갖습니다!

워크플로 배포 역할 (OIDC — 07):
  ✔ 배포 권한, sub 조건으로 저장소·브랜치·환경 통제
  → 러너에서 configure-aws-credentials로 assume
EOF
```

핵심 실험 — 러너에서 OIDC가 여전히 동작하는가:

```bash
cat > .github/workflows/oidc-on-runner.yml <<EOF
name: oidc-on-runner
on: workflow_dispatch
permissions: { id-token: write, contents: read }
jobs:
  deploy:
    runs-on: eks-runners
    steps:
      - name: OIDC 토큰은 러너 종류와 무관합니다
        run: |
          if [ -n "\$ACTIONS_ID_TOKEN_REQUEST_URL" ]; then
            echo "✅ self-hosted 러너에서도 OIDC 토큰 요청 가능"
          fi
      # 실제로는: aws-actions/configure-aws-credentials로 07의 역할 assume
EOF
git add -A && git commit -qm "test: oidc on self-hosted" && git push -q
gh workflow run oidc-on-runner.yml && sleep 55
gh run view --log 2>/dev/null | grep "OIDC 토큰 요청 가능" | head -1
```

✅ **OIDC(07)는 러너 종류와 무관하게 동작합니다.** 그래서 배포 권한은 러너 Pod가 아니라 워크플로의 OIDC 역할에 둡니다 — 러너는 실행 환경일 뿐 권한 주체가 아닙니다.

## Step 6. 산출물 — self-hosted 보안 체크리스트

```markdown
# self-hosted 러너 보안 (ARC on EKS)
## 격리
- [x] ephemeral 러너만 (persistent 금지 — 자격증명·잔재 유출)
- [ ] dind 대신 rootless BuildKit 검토 (privileged 회피)

## 네트워크 (러너가 VPC 안에 있습니다)
- [ ] egress 기본 거부 + 필요한 대상만 (DNS, 443, 특정 DB만)
- [ ] IMDS hop limit=1 (노드 역할 탈취 차단 — eks 25)
- [ ] 러너 노드를 별도 서브넷/SG로 격리

## 저장소
- [ ] ★ 퍼블릭 저장소에는 절대 붙이지 않음
- [ ] 포크 PR 승인 필요 설정

## IAM (두 층)
- [ ] 러너 Pod 역할: 최소(ECR pull, 로그) — 배포 권한 없음
- [ ] 배포 권한: 워크플로의 OIDC 역할(07), sub 조건으로 통제

## 스케일 (eks 17)
- [ ] Karpenter CI NodePool: spot + taint + do-not-disrupt(긴 잡)
- [ ] minRunners는 콜드 스타트 vs 비용 균형으로
```

## Step 7. 중급 진도 점검

```markdown
06 → 재사용과 배포 통제(environments)          [ ]
07 → OIDC로 장기 키 제거 (04의 부채 상환)       [ ]
08 → self-hosted 러너: 자유와 그 책임           [ ]
→ 다음: 09~11(AWS Code 시리즈), 12(GitLab), 13(Jenkins) — GitHub 밖의 세계
```

## 정리

```bash
bash cleanup.sh
```
