# Lab 02 — 원정 ③④: 컨트롤러와 스케줄러의 심장

## 원정 ③ Deployment 컨트롤러 — "롤링 업데이트는 누가 하나"

### Step 1. 컨트롤러 매니저는 컨트롤러의 "아파트"

```bash
cd ~/go/src/k8s.io/kubernetes
ls pkg/controller/ | head -20      # deployment, job, cronjob... 모듈들이 전부 입주민
grep -rn "startDeploymentController" cmd/kube-controller-manager/app/apps.go
```

✅ controller-manager = 40여 개 컨트롤러를 한 프로세스에 모은 것. 각 start 함수가 informer를 공유받아 컨트롤러를 기동 — 모듈 31에서 조립한 그 구조가 40벌.

### Step 2. 배관 확인 — 우리가 만든 것과 같은 모양

```bash
grep -n "AddEventHandler\|workqueue" pkg/controller/deployment/deployment_controller.go | head -8
grep -n "func (dc \*DeploymentController) syncDeployment" pkg/controller/deployment/deployment_controller.go
```

✅ informer 핸들러 → 큐에 키 → 워커가 sync — **모듈 31 lab-02에서 맨손 조립한 바로 그 패턴**입니다. 차이는 비즈니스 로직의 깊이뿐.

### Step 3. 핵심 질문 추적 — "maxSurge는 어디서 계산되나"

```bash
ls pkg/controller/deployment/        # rolling.go가 눈에 띕니다
grep -n "maxSurge\|MaxSurge" pkg/controller/deployment/rolling.go | head -5
# 실제 산수는 util에:
grep -n "func MaxSurge\|func NewRSNewReplicas" pkg/controller/deployment/util/deployment_util.go | head
```

에디터로 `rolling.go`의 `rolloutRolling` → `reconcileNewReplicaSet`/`reconcileOldReplicaSets`를 읽어라. 모듈 04에서 **관측**했던 "새 RS 늘리고 옛 RS 줄이고"가 이 두 함수입니다.

✅ **원정 ③ 보고서**: Deployment는 Pod를 직접 안 만집니다 — RS의 replicas 숫자만 조정하고(rolling.go), Pod는 ReplicaSet 컨트롤러의 몫. "컨트롤러는 한 단계 아래 리소스만 책임진다"는 설계 원칙이 코드 구조로 보입니다.

### Step 4. 테스트로 명세 확인 (전술 ③)

```bash
grep -n "TestDeploymentController\|func Test" pkg/controller/deployment/rolling_test.go | head -8
```

테스트 이름들이 곧 동작 명세서: "scale up 케이스", "maxUnavailable 준수"... 44에서 내가 쓸 테스트의 견본입니다.

## 원정 ④ 스케줄러 — 모듈 25의 사이클을 원문으로

### Step 5. 한 Pod의 스케줄링 한 사이클

```bash
grep -n "func (sched \*Scheduler) ScheduleOne\|func (sched \*Scheduler) scheduleOne" pkg/scheduler/schedule_one.go | head -2
```

에디터에서 `scheduleOne`(또는 `ScheduleOne`)을 열고 모듈 25의 그림과 대조하며 읽어라:

```
schedulingCycle:  findNodesThatFitPod(Filter) → prioritizeNodes(Score)
                  → selectHost → assume(캐시 선반영)
bindingCycle:     go func() { ... bind ... }   ← 병렬! (25에서 배운 그 이유)
```

```bash
# Filter 집계 메시지("0/5 nodes are available")의 출생지도 찾아보세요
grep -rn "nodes are available" pkg/scheduler/ | grep -v _test | head -2
```

✅ 모듈 38에서 읽던 진단 메시지가 만들어지는 함수까지 — 사용자 경험과 코드가 한 줄로 이어졌습니다.

### Step 6. 플러그인 한 개 정독 — NodeAffinity

```bash
wc -l pkg/scheduler/framework/plugins/nodeaffinity/node_affinity.go    # 의외로 짧습니다
grep -n "func.*Filter\|func.*Score" pkg/scheduler/framework/plugins/nodeaffinity/node_affinity.go
```

✅ 플러그인 하나 = Filter/Score 메서드 구현체. 모듈 12의 YAML(nodeAffinity)이 어떻게 평가되는지 끝까지 읽힙니다 — **"내 플러그인을 추가한다면"의 견본이기도** 합니다(25 lab-02의 두 번째 스케줄러 + 이 코드 = 커스텀 플러그인 개발의 전부).

### Step 7. 소유권 확인 → 43으로

```bash
cat pkg/scheduler/OWNERS            # sig/scheduling
cat pkg/controller/deployment/OWNERS # sig/apps
```

✅ 원정한 코드의 주인 SIG를 확인했습니다 — 이들의 회의/슬랙/이슈가 모듈 43의 무대입니다.

## 원정 기록 (산출물)

```markdown
# 코드 원정 노트 ③④
- 컨트롤러 공통 골격 = informer→queue→sync (모듈 31과 동일) — 새 컨트롤러 읽기는 sync부터
- Deployment의 롤링 = rolling.go (RS 숫자 조정만, Pod는 RS 컨트롤러)
- 스케줄러 = schedule_one.go의 두 사이클, 플러그인은 framework/plugins/<이름>/
- "0/N nodes available"의 출생지 확인됨
- 주인: scheduler=sig-scheduling, deployment=sig-apps (OWNERS)
```

> cleanup 없음 — 읽기만 했습니다. 단, 에디터에서 실수로 저장한 변경이 없는지: `git status`
