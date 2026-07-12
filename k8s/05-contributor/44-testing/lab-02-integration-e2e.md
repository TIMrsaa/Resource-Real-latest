# Lab 02 — integration, e2e, 그리고 prow의 언어

## Part A. integration — 진짜 API 서버를 테스트 안에서

### Step 1. etcd 준비 확인 (모듈 41에서 설치)

```bash
cd ~/go/src/k8s.io/kubernetes
ls third_party/etcd/etcd 2>/dev/null || hack/install-etcd.sh
export PATH="$(pwd)/third_party/etcd:$PATH"
etcd --version | head -1
```

### Step 2. 좁혀서 한 묶음 실행

```bash
# garbage collector 통합 테스트 (모듈 24의 GC가 진짜 API 서버에서 검증되는 곳)
time make test-integration WHAT=./test/integration/garbagecollector \
  KUBE_TEST_ARGS="-run TestCascadingDeletion" 2>&1 | tail -8
```

예상: 테스트 안에서 etcd+API 서버가 기동되고(로그에 보입니다), 수 분 내 ok.

✅ **unit과의 차이 체감**: fake client였다면 ownerReference를 "그냥 저장"하지만, 여기선 진짜 GC 컨트롤러가 cascade 삭제를 수행한 결과를 검증합니다 — admission/GC/실제 저장 계층이 전부 진짜.

### Step 3. integration 테스트 코드 훑기

```bash
grep -n "func TestCascadingDeletion" test/integration/garbagecollector/garbage_collector_test.go
```

에디터로 열어 골격만: 프레임워크 기동(`kubeapiservertesting.StartTestServer` 류) → 진짜 clientset으로 리소스 생성 → poll로 결과 대기. **"테스트가 미니 클러스터를 소유한다"**는 모양을 봐두라 — 내 변경이 admission/스토리지에 닿으면 이 층의 테스트가 필요해집니다.

## Part B. e2e — 읽을 줄 알면 됩니다

### Step 4. e2e 코드의 모양 (ginkgo)

```bash
grep -rn "framework.ConformanceIt\|ginkgo.It" test/e2e/apps/deployment.go | head -5
```

```go
// 이런 모양입니다:
framework.ConformanceIt("RollingUpdateDeployment should delete old pods ...", func(ctx ...) {
    // 진짜 클러스터에 Deployment 만들고 → 롤링 후 옛 Pod 정리를 사용자 시점에서 검증
})
```

✅ `[Conformance]` 딱지 = **모든 인증 배포판이 통과해야 하는 계약** — 우리가 쓰던 EKS도 이 테스트들을 통과한 물건입니다. e2e는 "코드 검증"이라기보다 "약속 검증"입니다.

### Step 5. (선택, 무거움) kind에서 e2e 하나만 돌려보기

```bash
kind create cluster --name e2e-lab 2>/dev/null || true
# e2e 바이너리 빌드 후 초경량 실행 (시간 있을 때만)
make WHAT=test/e2e/e2e.test
./_output/bin/e2e.test --kubeconfig=$HOME/.kube/config \
  --ginkgo.focus="Kubectl client Kubectl version" --provider=skeleton 2>&1 | tail -5
kind delete cluster --name e2e-lab
```

> 실패해도 좌절 금지 — e2e 로컬 실행은 숙련자도 까다로워합니다. CI(prow)가 돌려주는 걸 읽는 능력이 우선.

## Part C. prow — PR 화면에서 보게 될 것들

### Step 6. 실제 PR의 CI를 "관전"

브라우저에서 kubernetes/kubernetes의 아무 열린 PR(활발한 것)을 열고 체크리스트:

```markdown
# prow 관전 체크리스트
- [ ] k8s-ci-robot이 단 라벨들: size/M, sig/apps, cncf-cla: yes ...
- [ ] Checks 탭의 잡 목록: pull-kubernetes-unit, -verify, -e2e-kind ...
- [ ] 실패한 잡 하나 클릭 → 로그 → 어느 테스트가 왜 죽었나 찾아보기
- [ ] 코멘트의 명령들: /retest, /lgtm, /approve, /ok-to-test 가 실제로 쓰이는 모습
- [ ] testgrid.k8s.io 에서 pull-kubernetes-unit 잡의 최근 성적 보기 (flake 감각)
```

✅ 45에서 **내 PR에 이 화면이 그대로** 펼쳐집니다 — 미리 본 사람과 처음 보는 사람의 침착함이 다릅니다.

### Step 7. flake 판별 연습 (시나리오)

> 내 PR(주석 오타 수정)에서 `pull-kubernetes-e2e-kind`가 빨갛습니다. 어떻게 하나요?

```
① 로그에서 실패 테스트 확인 → 네트워크 타임아웃, 내 변경과 무관해 보임
② testgrid에서 그 테스트 검색 → 최근 며칠 간헐 실패 (flaky 후보)
③ 결론: /retest 코멘트 (한 번) → 통과
④ 만약 같은 곳이 반복 실패라면: 내 변경 재검토 → 그래도 무관하면
   kubernetes/kubernetes 이슈에서 해당 테스트명 검색 (flake 이슈 존재 여부)
```

✅ "빨간 CI에 당황하지 않고 절차로 대응" — 이게 이 lab의 최종 산출물입니다.

## 정리

```bash
bash cleanup.sh
```
