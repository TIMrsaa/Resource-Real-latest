# Lab 02 — 커뮤니티 입주와 기여 행정

> 이 lab의 산출물은 코드가 아니라 **계정/구독/서명** — 45에서 PR을 보내는 순간 전부 필요해집니다. 오늘 다 해두면 그날 막힘이 없습니다.

## Step 1. CLA 서명 (PR의 필수 조건)

1. https://github.com/kubernetes/community/blob/master/CLA.md 의 절차대로
2. 개인 기여자: Linux Foundation의 EasyCLA에서 개인 CLA 서명 (회사 소속으로 업무 기여라면 회사 CCLA — 회사 절차 확인)
3. 확인: 서명 후 첫 PR에서 봇(`cncf-cla` 체크)이 초록색이면 성공

> 서명 전 PR을 올리면 봇이 `cncf-cla: no` 라벨로 차단합니다 — 지금 해두는 이유.

## Step 2. Slack 입주

1. https://slack.k8s.io 에서 초대 → 워크스페이스 가입
2. 필수 채널: `#kubernetes-novice` (입문 질문), `#kubernetes-contributors` (기여 일반)
3. 관심 SIG 채널 2개: 추천 `#sig-node`, `#sig-cli` (42 원정에서 본 코드의 주인들)
4. **첫 미션**: 각 SIG 채널의 최근 1주 대화를 훑어라 — 무엇이 논의되는지, 어떤 톤인지. (눈팅도 입주입니다)

## Step 3. 메일링리스트 구독

- dev@kubernetes.io (groups.google.com/g/kubernetes-dev) — 프로젝트 전체 공지/논의
- 관심 SIG 리스트 1개 (예: kubernetes-sig-node)

> 메일이 많습니다 — 필터로 폴더 분리 추천. 릴리스 일정/중대 변경/회의 공지가 흐르는 곳이라 끊지는 말 것.

## Step 4. SIG 회의 참관 (이번 주 안에)

1. SIG 목록에서 관심 SIG의 회의 시간 확인: https://github.com/kubernetes/community/blob/master/sig-list.md
   (한국 시간으로 새벽인 경우가 많습니다 — 그래서 ↓)
2. **녹화로 참관해도 충분**: YouTube "Kubernetes Community" 채널의 해당 SIG 재생목록에서 최근 회의 1편
3. 들으며 메모: 안건은 어디서 오나(회의 문서 링크), 결정은 어떻게 내려지나, KEP이 언급되는 방식

✅ 참관 보고 한 줄(무슨 안건이 어떻게 처리됐나)을 쓸 수 있으면 이 Step 통과.

## Step 5. 기여 대상 정찰 — good first issue 지도

45의 사전 정찰. 아직 잡지 말고 **지형만**:

```
검색 쿼리 (GitHub):
  repo:kubernetes/kubernetes label:"good first issue" state:open
  repo:kubernetes/kubernetes label:"help wanted" label:"sig/cli" state:open
주변 리포도 좋은 사냥터 (경쟁 덜함):
  kubernetes-sigs/kind, kubernetes-sigs/kustomize, kubernetes/website (문서!)
```

관찰 포인트:
- 이슈에 `/assign` 한 사람이 이미 있나 (선점됨)
- 며칠 안에 사라지는가 (인기 이슈의 속도)
- 어떤 SIG 라벨이 입문 이슈를 많이 내나

✅ 후보 이슈 3개를 북마크 — 잡는 건 45에서.

## Step 6. 입주 완료 체크리스트 (산출물)

```markdown
# 커뮤니티 입주 체크리스트 — 2026-MM-DD
- [ ] CLA 서명 완료 (EasyCLA)
- [ ] GitHub 2FA 활성
- [ ] Slack: #kubernetes-novice, #kubernetes-contributors, #sig-__, #sig-__
- [ ] 메일링리스트: dev@, sig-__
- [ ] SIG 회의 1편 참관 (안건: ______, 배운 것: ______)
- [ ] good first issue 후보 3개: #____, #____, #____
다음(모듈 45): 후보 중 하나에 /assign
```

> cleanup 없음 — 오늘 만든 것들은 지우는 게 아니라 **유지하는 것**이 과제입니다.
