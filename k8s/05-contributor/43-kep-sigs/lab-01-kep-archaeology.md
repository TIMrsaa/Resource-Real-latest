# Lab 01 — KEP 고고학: 기능 하나의 일대기 추적

> 대상: **Sidecar Containers** (모듈 14/29에서 사용자로 만난 그 기능). "써본 기능"의 서류를 파면 KEP 읽기가 단숨에 늡니다. (다른 기능으로 해도 됨 — 절차는 동일)

## Step 1. KEP 찾기

```bash
git clone --depth 1 https://github.com/kubernetes/enhancements.git ~/enhancements
cd ~/enhancements
grep -rln "sidecar" keps/ --include="*.md" | head -5
ls keps/sig-node/753-sidecar-containers/
```

> 웹으로 해도 됩니다: github.com/kubernetes/enhancements에서 "sidecar" 검색. 번호(753)는 원 이슈 번호입니다.

## Step 2. kep.yaml — 신상명세서부터

```bash
cat keps/sig-node/753-sidecar-containers/kep.yaml
```

확인할 것:
```yaml
owning-sig: sig-node            # 주인 (42에서 kubelet 코드의 OWNERS와 일치!)
stage: stable                    # 현재 단계
latest-milestone: "1.NN"         # 단계 변화가 일어난 버전
feature-gates: [SidecarContainers]   # 모듈 29의 그 gate 이름
```

✅ **kep.yaml = 기능의 주민등록증.** 어느 SIG가, 어느 버전에서, 어떤 gate로 — 30초 만에 파악.

## Step 3. README 정독 — 순서가 중요합니다

`keps/sig-node/753-sidecar-containers/README.md`를 다음 순서로:

1. **Summary/Motivation**: "왜 initContainers+restartPolicy: Always라는 이상한 모양이 됐는지"의 답이 여기 있습니다 — 새 필드(`sidecarContainers:`)를 추가하는 대안과 비교 끝에 내린 결정
2. **Non-Goals**: "사이드카의 시작 순서 보장은 다루되, 임의 의존성 그래프는 안 한다" 류 — 범위의 경계선
3. **Alternatives**: 버려진 설계들과 버린 이유 — **여기가 설계 감각이 가장 많이 느는 섹션**
4. **Graduation Criteria**: Alpha→Beta→GA 각각의 조건 — "e2e 테스트, 피드백 수렴, 업그레이드 경로..."

✅ 모듈 14에서 "왜 이런 문법이지?"라고 느꼈다면, 그 의문의 공식 답변서를 방금 읽었습니다.

## Step 4. 역사 추적 — 회의실까지

KEP 디렉터리의 git 이력과 PR 논의:

```bash
git log --oneline -- keps/sig-node/753-sidecar-containers/ | tail -5   # 단계 승격의 순간들
```

웹에서:
- kubernetes/enhancements의 해당 파일 → History → 승격 PR의 리뷰 코멘트 (반대 의견과 해소 과정!)
- 원 이슈(#753)로 가면: **2018년부터의 긴 논의** — 한 번 폐기됐다가 부활한 역사까지 보입니다

✅ "기능 하나 = 수년의 공개 토론"이라는 현실. 그리고 그 토론에 누구나(우리도) 참여할 수 있었다는 사실.

## Step 5. 구현 코드와 연결 (41~42 총동원)

```bash
cd ~/go/src/k8s.io/kubernetes
# feature gate 정의 위치
grep -rn "SidecarContainers" pkg/features/kube_features.go | head -3
# 게이트로 분기하는 실제 코드
grep -rln "SidecarContainers" pkg/kubelet/ pkg/api/ | head -5
```

✅ **서류(KEP) → 스위치(feature gate) → 코드(kubelet)** 의 삼위일체 확인. 모듈 29의 "기능 발굴 루틴"이 이제 역방향으로도 가능합니다: 코드의 gate를 보고 → KEP을 찾아 → 설계 의도를 읽습니다.

## Step 6. 원정 보고서 (산출물)

```markdown
# KEP 고고학 보고서 — SidecarContainers (#753)
- 주인: sig-node / gate: SidecarContainers / 현재: stable
- 핵심 결정: 새 필드 대신 initContainers+restartPolicy 재사용 — 이유: (Alternatives에서 요약)
- 한 번 폐기 후 부활 — 교훈: 거절은 끝이 아니라 "지금은 아니다"
- 내가 다음에 팔 KEP 후보: (모듈 29에서 궁금했던 기능 하나 적기)
```

## 도전 과제 (선택)

모듈 29에서 다룬 다른 기능 하나(예: In-Place Pod Resize)의 KEP을 같은 절차로 30분 안에 추적해보세요 — 두 번째는 절반의 시간이면 된다는 걸 확인하는 것이 목적.
