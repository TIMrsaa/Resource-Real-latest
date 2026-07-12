# Lab 02 — 이슈 드래프트: 마찰을 논증으로 벼리기

지난 26개 모듈에서 만난 마찰 하나를 골라, **제출 가능한 품질**의 이슈를 씁니다. (실제 제출은 중복 검색과 자기 판단 후 — 이 랩은 드래프트까지)

## Step 1. 재료 고르기 — 우리가 실제로 겪은 것

```markdown
# 마찰 후보 (각자 겪은 것에 ✓)
- [ ] 04 Auto Mode: 노드 접근이 없어 특정 진단이 불가능합니다
- [ ] 06 Fargate: DaemonSet 미지원으로 로그/메시 사이드카 전략이 갈립니다
- [ ] 11 애드온: configuration-values 스키마에 필요한 옵션이 없어 자가 관리로 이탈해야 했습니다
- [ ] 16 IP: custom networking 적용 시 max-pods가 줄어 prefix delegation을 강제로 병행
- [ ] 19 GPU: time-slicing 설정이 애드온 스키마로 노출되지 않습니다
- [ ] 기타: __________ (실제로 막혔던 것만! 상상한 불편은 재료가 아닙니다)
```

선택 기준: **재현 가능하고, 영향을 숫자로 말할 수 있는 것.** 둘 중 하나가 없으면 다른 재료를 고르라.

## Step 2. 증거 수집 — 재현 절차를 명령으로

이슈의 신뢰는 여기서 만들어집니다. 예로 "custom networking + max-pods 하락"(16)을 쓴다면:

```bash
# 버전 고정 (반드시 명시)
aws eks describe-cluster --name k8s-study --query 'cluster.version' --output text
kubectl get ds aws-node -n kube-system -o jsonpath='{.spec.template.spec.containers[0].image}'; echo

# 증상의 수치화 — 전/후 max-pods
kubectl get nodes -o custom-columns='NODE:.metadata.name,TYPE:.metadata.labels.node\.kubernetes\.io/instance-type,MAXPODS:.status.allocatable.pods'
```

수집 원칙: ① 버전(CP, 애드온, CLI) ② 최소 재현 명령 ③ 실제 출력(마스킹) ④ 기대 vs 실제.

## Step 3. 영향 정량화 — 비교 가능한 숫자로

```markdown
# 정량화 워크시트 (셋 중 최소 하나)
- 비용: "노드 __대 → __대 (+__%), 월 약 $__" (22의 계량 능력을 여기서 씁니다)
- 시간: "배포마다 __초의 5xx", "장애 진단에 평균 __분 추가"
- 위험: "우회책이 X를 비활성화해야 해서 보안 관문 ⑤를 잃습니다(25)"
```

숫자가 없으면 이슈는 "불편하다"의 변주일 뿐입니다 — 제품팀이 다른 요청과 비교할 수 없습니다.

## Step 4. 드래프트 작성

```bash
mkdir -p contrib && cat > contrib/issue-draft.md <<'EOF'
## Community Note
* Please vote on this issue by adding a 👍 reaction to the original issue
* Please do not leave "+1" comments — they generate extra noise

## Tell us about your request
<한 문장. "무엇이 가능하기를 원하는가" — 구현 방식이 아니라 능력으로.>

## Which service(s) is this request for?
EKS / <해당 컴포넌트>

## Tell us about the problem you're trying to solve. What are you trying to do, and why is it hard?
**What we're doing**
<우리 워크로드/운영 맥락 2~3문장. 왜 이걸 하려는지.>

**Where it breaks**
Versions: EKS <x.y>, <addon> <ver>, <cli> <ver>

Steps to reproduce:
1. `<명령>`
2. `<명령>`

Expected: <기대>
Actual: <실제 출력 — 마스킹>

**Impact**
- <정량화 1: 비용/대수/시간/위험>
- <정량화 2>

## Are you currently working around this issue?
<우회책과 그 한계. 없으면 "No workaround; we are blocked on ...">

## Additional context
<링크, 관련 이슈 번호(#123), 매니페스트 — 계정 ID/ARN/IP 마스킹 확인>
EOF
echo "드래프트: contrib/issue-draft.md"
```

## Step 5. 자가 리뷰 — 제출 전 체크리스트

```markdown
- [ ] 중복 검색 완료 (open + closed) — 있다면 이슈 대신 👍+댓글로 전환
- [ ] 해결책을 강요하지 않았습니다 (문제와 제약을 서술했습니다)
- [ ] 다른 사람이 내 명령만으로 재현할 수 있습니다
- [ ] 영향이 숫자입니다 (비교 가능합니다)
- [ ] 우회책과 그 한계를 밝혔습니다 (대안 검토의 증거)
- [ ] 민감정보 없음 (계정 ID, ARN, IP, 내부 도메인)
- [ ] 문이 맞습니다 (클로즈드→로드맵 / 오픈소스→그 저장소 / 개별 장애→서포트)
- [ ] 톤: 비난이 아니라 협업 — 읽는 사람은 이 문제를 만든 적 없는 엔지니어입니다
```

## Step 6. 다음 층으로 — 문서 PR 한 건 (진짜 첫 기여)

가장 확실한 첫 기여는 문서입니다. 지금 이 커리큘럼을 쓰며 발견한 문서의 오류·누락이 있다면:

```bash
# 예: EKS Best Practices에 기여
gh repo fork aws/aws-eks-best-practices --clone
cd aws-eks-best-practices && git checkout -b fix/typo-in-networking
# ... 수정 ...
git commit -am "docs: fix incorrect max-pods formula in custom networking section"
gh pr create --fill
```

✅ 문서 PR이 병합되면 당신은 **AWS 오픈소스 컨트리뷰터**입니다 — 그리고 그 신뢰가 29의 코드 PR을 더 빨리 읽히게 합니다(theory §5의 사다리).

## 정리

```bash
bash cleanup.sh    # 드래프트는 보존 — contrib/는 당신의 자산
```
