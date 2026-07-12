# 이론 — Scheduling Framework 해부

> **🌱 17세 눈높이 비유: 오디션 프로그램의 심사 파이프라인**
> 지원자(Pod)가 무대에 오르면: **서류 심사**(Filter — 자격 미달 즉시 탈락) → **점수 심사**(Score — 심사위원들이 각자 점수, 가중 합산) → **최고점 선발**(노드 확정) → 그런데 **계약서 서명**(Bind)은 시간이 걸려서, 그 동안 다음 지원자 심사를 계속합니다(병렬 바인딩).
> 전원 탈락이면? **패자부활 심사**(PostFilter = 선점)가 "기존 합격자 중 누굴 떨어뜨리면 이 지원자가 들어가나"를 계산합니다.

---

## 1. 두 개의 사이클

```
[스케줄링 사이클 — 한 번에 Pod 하나, 직렬]
PreEnqueue → (큐) → QueueSort
→ PreFilter → Filter → PostFilter(전멸 시: 선점)
→ PreScore → Score → NormalizeScore
→ Reserve → Permit
[바인딩 사이클 — 비동기, 병렬]
→ PreBind → Bind → PostBind
```

- **스케줄링 사이클은 직렬**(한 번에 1 Pod) — 결정의 일관성을 위해. **바인딩은 병렬** — API 호출(느림)이 다음 Pod 결정을 막지 않게
- **Reserve**: 바인딩이 끝나기 전에 "이 노드의 자원은 이 Pod 것"이라고 **캐시에 선점 기록** — 직렬 결정과 병렬 바인딩 사이의 정합성 다리
- Permit: 대기/거부 가능 — 갱 스케줄링(전원 모이면 한꺼번에 — ML 학습 잡)의 확장점

## 2. 단계별 핵심

### 큐 — 그냥 FIFO가 아닙니다

```
activeQ          지금 심사 대기 (priority 정렬 — QueueSort 플러그인)
backoffQ         실패 후 잠시 대기 (지수 백오프: 1s→2s→...→10s)
unschedulablePods  "지금은 안 됨" 보관소 — 클러스터 이벤트(노드 추가 등)가 깨움
```

"노드를 비웠는데 Pending이 바로 안 풀리는" 이유 = backoff. "영원히 안 풀리는" 경우 = 깨울 이벤트가 안 오는 상황(드물지만 버그성 — 재시도 트리거인 QueueingHint가 이를 정밀화).

### Filter — 탈락 사유의 집계가 곧 에러 메시지

각 노드에 대해 모든 Filter 플러그인 실행 (병렬, 노드 단위). **하나라도 거부하면 그 노드 탈락.** 전 노드 탈락 시의 사유 집계가 우리가 보는 메시지입니다:

```
0/5 nodes are available: 2 Insufficient cpu,        ← NodeResourcesFit가 2대 탈락시킴
1 node(s) had untolerated taint {team: ml},          ← TaintToleration이 1대
2 node(s) didn't match pod affinity rules.           ← InterPodAffinity가 2대
```

### Score — 성향이 결정되는 곳

각 플러그인이 노드마다 0~100점 + 플러그인별 **가중치** 곱해 합산. 기본 성향:

| 플러그인 | 기본 성향 |
|----------|----------|
| NodeResourcesFit (LeastAllocated) | **여유 많은 노드 선호** = 퍼뜨리기(spreading) |
| 〃 (MostAllocated로 설정 시) | 꽉 채우기(bin-packing) — 노드 수 절약(비용!) |
| ImageLocality | 이미지 이미 있는 노드 선호 (풀 시간 절약) |
| PodTopologySpread | 분산 제약 점수화 |

> **💡 비용과의 연결**: 기본(LeastAllocated)은 노드를 넓게 쓰므로 **노드 수가 줄지 않습니다.** Karpenter가 consolidation으로 빈 노드를 회수하는 것과, 스케줄러를 MostAllocated로 바꾸는 것이 같은 문제(bin-packing)에 대한 두 접근입니다 — eks 파트 17에서 합류.

### PostFilter — 선점의 실체

전 노드 탈락 시 DefaultPreemption 플러그인이: "어느 노드에서 **어떤 낮은 priority Pod들을 빼면** 이 Pod가 들어가는가"를 시뮬레이션 → 희생자 최소 조합 선택 → 희생자 삭제 + `nominatedNodeName` 기록 (모듈 12 lab-02에서 목격한 그 동작).

## 3. 설정 — KubeSchedulerConfiguration

```yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
profiles:
- schedulerName: default-scheduler
  pluginConfig:
  - name: NodeResourcesFit
    args:
      scoringStrategy:
        type: MostAllocated          # bin-packing으로 성향 변경!
- schedulerName: batch-scheduler     # 한 바이너리에 멀티 프로파일도 가능
  plugins:
    score:
      disabled: [{ name: ImageLocality }]
```

- Pod는 `spec.schedulerName`으로 프로파일/스케줄러 선택
- **EKS 제약**: 기본 스케줄러의 설정은 못 바꿉니다(관리형) → 성향 변경이 필요하면 **두 번째 스케줄러를 Pod로 배포** — lab-02에서 실제로 합니다

## 4. 성능 한 토막

- 대규모 클러스터에서 모든 노드를 다 채점하지 않습니다: `percentageOfNodesToScore` — "충분히 좋은" 노드를 빨리 찾는 트레이드오프
- 스케줄러 처리량 병목은 보통 InterPodAffinity(전 노드 Pod 검사 — 모듈 12에서 "비싸다"고 한 이유)

## 5. 소스코드에서 확인하기

- 프레임워크 정의: `pkg/scheduler/framework/interface.go` — 확장점 인터페이스 전부가 한 파일에
- 사이클 본체: `pkg/scheduler/schedule_one.go` — `schedulingCycle`/`bindingCycle` 함수가 위 그림 그대로
- 플러그인들: `pkg/scheduler/framework/plugins/` — 디렉터리명이 곧 기능명
- 선점: `pkg/scheduler/framework/preemption/`

## 요약 카드

| 질문 | 답 |
|------|----|
| 결정은 직렬, 바인딩은 병렬인 이유? | 일관된 결정 + 느린 API 호출의 비차단 |
| Reserve의 역할? | 바인딩 완료 전 캐시 선점 — 이중 배정 방지 |
| Pending 메시지의 정체? | Filter 플러그인별 탈락 노드 수 집계 |
| 퍼뜨리기 vs 채우기 전환? | NodeResourcesFit scoringStrategy (Least/MostAllocated) |
| EKS에서 성향 변경법? | 두 번째 스케줄러 배포 + spec.schedulerName |
| 선점이 일어나는 단계? | PostFilter (전 노드 탈락 시) |
