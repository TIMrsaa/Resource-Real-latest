# Lab 01 — 콘솔 6개 탭 투어 + 권한 수수께끼

> 브라우저: AWS 콘솔 → EKS → 클러스터 → k8s-study. 각 Step의 ✅를 채워가며 진행.

## Step 1. 개요 탭 — 모듈 01 lab-01의 GUI판

체크리스트:
```markdown
- [ ] 버전 1.36 / 플랫폼 버전 eks.__ (describe-cluster와 일치 확인)
- [ ] "지원 종료" 날짜 표기 발견 (연장 지원 진입일 — 달력에!)
- [ ] API 서버 엔드포인트와 OIDC issuer (lab에서 본 그 값)
```

## Step 2. 리소스 탭 — 콘솔이 kubectl을 대신 쳐줍니다

1. 리소스 탭 → 워크로드 → Pod: kube-system의 Pod들이 보이는가요?
2. 같은 화면을 kubectl로 대조: `kubectl get pods -n kube-system`

✅ 같은 목록 — **같은 API, 같은 권한 경로**(theory §2)이므로 당연합니다. 다르게 보이면 그게 이상한 것.

## Step 3. 권한 수수께끼 재현 — "콘솔에서 안 보여요"

모듈 02의 eks-newbie 역할이 남아 있다면(없으면 lab-02 Step 1~2로 재생성), **그 역할로 콘솔에 들어가는 대신** 원리만 검증합니다:

```bash
# newbie의 entry에서 View 정책을 잠시 제거
export AWS_REGION=ap-northeast-2; export CLUSTER=k8s-study
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws eks disassociate-access-policy --cluster-name $CLUSTER --region $AWS_REGION \
  --principal-arn arn:aws:iam::$ACCOUNT_ID:role/eks-newbie \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy 2>/dev/null || echo "(역할 없음 — 02 lab-02 참고)"
# 그 역할로 K8s API를 치면 (assume-role 후):
# kubectl get pods → Forbidden — 콘솔이었다면 "리소스를 표시할 수 없음" 배너
```

✅ **콘솔의 "리소스 표시 불가" = 그 IAM의 K8s 권한 부재** — 콘솔 문제도 브라우저 문제도 아닙니다. 해결은 항상 access entry/policy(모듈 02). 사내에서 이 질문을 받으면: "콘솔에 로그인한 IAM이 뭐예요?"가 첫 질문입니다.

```bash
# 원복
aws eks associate-access-policy --cluster-name $CLUSTER --region $AWS_REGION \
  --principal-arn arn:aws:iam::$ACCOUNT_ID:role/eks-newbie \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy \
  --access-scope type=cluster 2>/dev/null || true
```

## Step 4. 컴퓨팅/네트워킹/추가 기능 탭

```markdown
- [ ] 컴퓨팅: 노드그룹의 desired/min/max (01 lab-02에서 만진 값) + 노드 헬스 "정상"
- [ ] 네트워킹: 서브넷 목록과 "남은 IP" 감각 (eks 07/16의 무대) + 엔드포인트 접근 설정
- [ ] 추가 기능: vpc-cni / coredns / kube-proxy 버전과 상태 — "업데이트 가능" 표시 여부
```

## Step 5. 액세스 탭 — 모듈 02의 GUI

```markdown
- [ ] IAM 액세스 항목에서: 나(생성자), 노드 역할, (있다면) eks-newbie/deploy-bot
- [ ] 각 항목의 정책/스코프가 lab-02에서 CLI로 본 것과 일치
```

✅ 감사 면담에서 "누가 클러스터 접근 가능하죠?"에 화면 한 장으로 답하는 곳.

## Step 6. 관측성 탭 — 운영자의 상황판

```markdown
- [ ] insights: 업그레이드 인사이트 목록 (k8s 35에서 CLI로 본 그것) — 경고 있으면 클릭해 상세
- [ ] control plane 로깅 on/off 상태 (k8s 21 lab-02와 연결)
- [ ] 메트릭/Container Insights 연결 여부 (eks 12에서 켭니다)
```

## 투어 보고서 (산출물)

```markdown
# 콘솔 투어 메모
- 매일 볼 화면: 관측성 insights / 컴퓨팅 노드 헬스
- 권한 오류 공식: 콘솔 리소스 뷰 오류 = 로그인 IAM의 entry 문제 (02로 해결)
- 콘솔에서 "수정"하고 싶어진 것: ______ → 실제로는 (CLI/IaC/kubectl) 로 할 것
```
