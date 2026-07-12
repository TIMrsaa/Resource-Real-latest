# Lab 01 — 로드맵 읽기: 신호와 소음을 구분하는 눈

기여의 0층은 읽기입니다. 로드맵을 데이터로 다뤄보고, 좋은 이슈와 나쁜 이슈를 실물로 감별합니다.

## Step 1. 도구 — gh CLI로 로드맵 훑기

```bash
# gh 설치 후 인증 (https://cli.github.com)
gh auth status || gh auth login

# EKS 라벨의 미해결 이슈, 👍 많은 순 — "커뮤니티가 가장 원하는 것"
gh issue list --repo aws/containers-roadmap --label EKS --state open \
  --limit 20 --json number,title,reactionGroups \
  --jq 'map({n:.number, t:.title,
             up:( .reactionGroups[]? | select(.content=="THUMBS_UP") | .users.totalCount ) // 0 })
        | sort_by(-.up) | .[] | "\(.up)👍  #\(.n)  \(.t)"'
```

읽는 법: 상위 이슈들이 **커뮤니티의 집단 고통 지도**입니다. 우리가 만난 마찰(16의 IP 고갈, 06의 Fargate 제약 등)이 이미 거기 있는지 확인하세요.

## Step 2. 상태 라벨의 지형 — 무엇이 움직이나

```bash
for L in "Researching" "We're Working On It" "Coming Soon"; do
  C=$(gh issue list --repo aws/containers-roadmap --label EKS --label "$L" --state open --limit 100 --json number --jq 'length')
  printf "%-22s %s건\n" "$L" "$C"
done
```

✅ `Coming Soon`에 있는 항목은 이슈를 새로 열 필요가 없습니다 — 기다리거나, 그 이슈에 유스케이스를 보태라(설계에 반영될 수 있는 마지막 시점).

## Step 3. 우리가 만난 마찰이 이미 있는가 — 중복 검색 훈련

이슈를 열기 전 **반드시** 하는 일. 닫힌 것까지 포함해 검색:

```bash
# 예: 16에서 만난 IP 고갈/prefix delegation 관련
gh search issues --repo aws/containers-roadmap "prefix delegation" --state all --limit 10 \
  --json number,title,state --jq '.[] | "[\(.state)] #\(.number) \(.title)"'

# 예: 06의 Fargate DaemonSet 제약
gh search issues --repo aws/containers-roadmap "fargate daemonset" --state all --limit 10 \
  --json number,title,state --jq '.[] | "[\(.state)] #\(.number) \(.title)"'
```

✅ 대부분 이미 존재합니다. 그렇다면 할 일은 새 이슈가 아니라 **👍 + 구체적 영향 댓글**(theory §1). 중복 이슈는 신호를 쪼개 우선순위를 떨어뜨립니다 — 도움이 아니라 방해입니다.

## Step 4. 감별 훈련 — 좋은 이슈의 해부

👍 상위 이슈 하나를 열어 본문 구조를 뜯어보세요:

```bash
N=<위에서 고른 이슈 번호>
gh issue view $N --repo aws/containers-roadmap --comments | head -80
```

체크리스트로 채점해보세요 (theory §3의 5부 구조):

```markdown
| 항목 | 있나요? | 메모 |
|------|-------|------|
| 한 문장 요청 (무엇을) | | |
| 문제 서술 (왜 — 무엇을 하려다 막혔나) | | |
| 재현 절차 / 버전 / 출력 | | |
| 영향 정량화 (비용·대수·시간) | | |
| 시도한 우회책과 한계 | | |
| 해결책을 강요하지 않음 | | |
| 댓글의 질 (+1 vs 구체적 유스케이스) | | |
```

그리고 대조군으로, 👍가 거의 없는 오래된 이슈 하나를 같은 표로 채점하세요. **차이가 대부분 위 항목들에 있음**을 발견할 것입니다 — 운이 아니라 구조입니다.

## Step 5. 문 고르기 연습 (판정 훈련)

각 상황에 맞는 통로를 고르라 (답: theory §2 결정 트리):

```markdown
| 상황 | 통로 |
|------|------|
| 1. "우리 클러스터만 CoreDNS가 죽는다" | |
| 2. "Fargate에서 DaemonSet을 쓰고 싶다" | |
| 3. "vpc-cni가 특정 조건에서 IP를 누수합니다(재현 가능)" | |
| 4. "ALB 컨트롤러 문서의 annotation 예제가 틀렸다" | |
| 5. "Karpenter의 consolidation 알고리즘을 개선하고 싶다" | |
| 6. "EKS 애드온 configuration-values에 X 옵션이 없다" | |

<!-- 답: 1=서포트 케이스 / 2=containers-roadmap / 3=amazon-vpc-cni-k8s 이슈(+PR — 29)
     4=문서 PR(가장 쉬운 첫 기여) / 5=Karpenter 코어(CNCF — 28) / 6=containers-roadmap -->
```

## 정리

읽기 전용. lab-02에서 직접 씁니다.
