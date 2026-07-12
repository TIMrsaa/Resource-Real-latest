# Lab 02 — 빌드, 테스트, 그리고 기여의 첫 걸음

네트워킹 코드를 클러스터 없이 검증하는 법을 익히고, 우리가 겪은 마찰(16의 불친절한 에러)을 실제 개선으로 벼립니다.

## Step 1. 빌드와 단위 테스트

```bash
cd ~/cni
go version                 # 1.23+
make unit-test 2>&1 | tail -15
```

수 분 안에 수천 개의 테스트가 통과합니다 — **클러스터도, AWS도, root 권한도 없이**. 비결을 확인하세요:

```bash
# netlink(커널 조작)를 인터페이스로 감싼 곳
grep -rn "type NetLink interface\|type netLink interface" pkg/networkutils/ cmd/routed-eni-cni-plugin/driver/ | head -3
# 그리고 그 mock
find . -path ./vendor -prune -o -name "*mock*" -print | head -5
```

✅ 28의 fake CloudProvider와 같은 사상 — **외부 세계(커널, EC2 API)를 인터페이스 뒤로 숨기면 테스트가 가능해집니다.** Go 컨트롤러 생태계 전체의 공통 문법이자, 당신이 다음에 쓸 컨트롤러의 설계 지침.

## Step 2. datastore 테스트 읽기 — 07의 회계가 명세로

```bash
grep -n "func TestAssignPodIPv4Address\|func TestGetIPStats\|func TestPodIPv4Address" pkg/ipamd/datastore/data_store_test.go | head
go test ./pkg/ipamd/datastore/... -count=1 -v 2>&1 | grep -E "^=== RUN|^--- (PASS|FAIL)" | head -12
```

테스트 이름이 곧 스펙입니다(28 Step 2의 교훈 재확인). warm pool·prefix 관련 테스트를 열어 우리 이론과 대조하세요.

## Step 3. 실습: 관측성 개선 — "왜 IP가 없는지" 말해주기

16 lab-01에서 우리는 IP 고갈을 진단하려고 `describe-subnets`와 ipamd 로그를 오갔습니다. 사용자가 겪은 그 불편이 기여의 재료입니다(theory §6).

목표: 할당 실패 시 로그에 **장부 상태**를 함께 남깁니다.

```bash
# 실패 경로 찾기
grep -rn "no available IP addresses" pkg/ | head -2
```

변경 스케치 (실제 코드는 버전마다 다르니 구조만):

```go
// before
return "", "", errors.New("assignPodIPv4AddressUnsafe: no available IP addresses")

// after — 진단에 필요한 맥락을 담습니다
stats := ds.GetIPStats(ipV4AddrFamily)
return "", "", fmt.Errorf(
    "assignPodIPv4AddressUnsafe: no available IP addresses "+
    "(total=%d assigned=%d cooldown=%d eniCount=%d) — "+
    "check subnet free IPs and WARM_IP_TARGET settings",
    stats.TotalIPs, stats.AssignedIPs, stats.CooldownIPs, len(ds.eniPool))
```

테스트를 **먼저** 씁니다(28 pitfall 4):

```go
It("should include datastore stats in the exhaustion error", func() {
    // 재고를 0으로 만든 뒤 할당 시도
    _, _, err := ds.AssignPodIPv4Address(...)
    Expect(err.Error()).To(ContainSubstring("total="))
    Expect(err.Error()).To(ContainSubstring("WARM_IP_TARGET"))
})
```

```bash
go test ./pkg/ipamd/datastore/... -count=1 2>&1 | tail -3
```

✅ 이 변경의 가치를 이슈로 설명할 수 있는가요? — "16에서 진단에 X분이 걸렸고, 이 로그 한 줄이면 즉시 판정됩니다." **27의 이슈 작성법(영향 정량화)이 여기서 회수됩니다.**

## Step 4. 이미지 빌드 — 그리고 배포하지 않기

```bash
make build-linux            # 바이너리
# make docker               # 이미지 (필요 시)
```

> ⚠️ **공유 클러스터의 aws-node를 커스텀 이미지로 바꾸지 말 것.** CNI가 죽으면 새 Pod가 뜨지 않고, 기존 Pod의 네트워크도 재시작 시 복구되지 않습니다 — 전 워크로드 장애입니다. 실험은 개인 계정의 일회용 EKS 클러스터에서, 그것도 노드 한 대짜리로.

검증이 필요하다면 저장소의 e2e 프레임워크를 쓰되(`test/`), 비용과 정리를 각오하고(28 pitfall 5).

## Step 5. 기여 제출 (28의 문법 그대로)

```bash
gh issue list --repo aws/amazon-vpc-cni-k8s --label "good first issue" --state open --limit 10 \
  --json number,title --jq '.[] | "#\(.number)  \(.title)"'

# 또는 관측성 개선을 이슈로 먼저 제안 (코드 PR 전에 합의를 얻는 것이 예의)
# → 27 lab-02의 이슈 템플릿 재사용: 문제·재현·영향·제안

git checkout -b feat/ip-exhaustion-error-context
git commit -s -m "feat(ipamd): include datastore stats in IP exhaustion error"
gh pr create --repo aws/amazon-vpc-cni-k8s --fill
```

체크리스트:

```markdown
- [ ] 테스트 포함 (동작 변경이면 필수)
- [ ] make unit-test 통과
- [ ] 로그에 민감정보(계정 ID, IP) 미포함 확인 — 이건 CNI입니다, 로그에 IP가 흔합니다!
- [ ] 변경이 성능 경로에 영향? (Pod 생성 경로의 코드는 지연에 민감)
- [ ] CHANGELOG/문서 갱신 필요 여부
```

## Step 6. 커리큘럼의 마지막 산출물

```markdown
# 나의 EKS 기여 계획 (27→28→29의 종합)
| 저장소 | 첫 행동 | 상태 |
|--------|---------|------|
| aws/containers-roadmap | 마찰 이슈 1건 (또는 👍+영향 댓글) | |
| aws/aws-eks-best-practices | 문서 PR 1건 | |
| kubernetes-sigs/karpenter | 테스트 PR 1건 | |
| aws/amazon-vpc-cni-k8s | 관측성 개선 이슈 → PR | |
| kubernetes/kubernetes | (k8s 45의 계획과 연결) | |

# 그리고 진짜 마지막 질문
이 커리큘럼 26개 모듈에서 내가 가장 오래 막혔던 것은 무엇인가요?
→ 그것이 나의 첫 기여 주제입니다. 막힘은 불운이 아니라 **아직 아무도 고치지 않은 자리**입니다.
```

## 정리

```bash
bash cleanup.sh
```
