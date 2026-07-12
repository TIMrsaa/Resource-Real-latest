# 이론 — Deployment, ReplicaSet, 롤링 업데이트, DaemonSet

> **🌱 17세 눈높이 비유: 편의점 본사의 운영 매뉴얼**
> - **ReplicaSet** = "우리 동네에 알바생 3명이 항상 근무해야 한다"는 규칙 + 그걸 지키는 매니저. 한 명이 그만두면 즉시 새로 뽑습니다. 단, **누가 우리 알바인지는 명찰(label)로만 판단**합니다.
> - **Deployment** = "유니폼을 구버전에서 신버전으로 교체하세요. 단, 매장이 한 번에 다 비면 안 된다"를 지휘하는 점장. 신버전 알바를 1명 뽑고, 구버전 1명을 보내고... 를 반복합니다.
> - **DaemonSet** = "모든 지점에 CCTV 관리자 1명씩" — 인원수가 아니라 **지점 수**에 따라 정해지는 역할.

---

## 1. ReplicaSet — 개수 유지 전담

```yaml
apiVersion: apps/v1
kind: ReplicaSet
spec:
  replicas: 3
  selector:                 # "내 Pod"를 식별하는 조건
    matchLabels:
      app: web
  template:                 # 부족할 때 새로 만들 Pod의 설계도
    metadata:
      labels:
        app: web            # ← selector와 반드시 일치해야 함
    spec:
      containers: [...]
```

조정 루프: `app=web` 라벨이 붙은 Pod 수를 셉니다 → 3과 다르면 만들거나 지웁니다. **그게 전부입니다.**

중요한 함의 — RS는 **라벨로만** 자기 Pod를 압니다:
- 내가 손으로 `app=web` 라벨을 붙인 Pod를 만들면? → RS가 "1개 초과네" 하고 **아무거나 하나 지웁니다**
- 기존 Pod에서 라벨을 떼면? → RS는 "1개 부족"으로 보고 새로 만듭니다. 라벨 떼인 Pod는 **고아가 되어 계속 돕니다** (lab-01에서 실험)

> **💡 ownerReferences**: 그래도 "누가 누구를 만들었는지"는 Pod의 `metadata.ownerReferences`에 기록됩니다. 부모를 지우면 자식이 연쇄 삭제되는 것(가비지 컬렉션)이 이 필드 덕분입니다 (고급 모듈 24).

## 2. Deployment — 버전 관리자

Deployment는 Pod를 직접 만들지 않습니다. **ReplicaSet을 만들고 갈아끼웁니다.**

### 2.1 롤링 업데이트의 실체

이미지를 v1 → v2로 바꾸면:

```
시각 0:  RS-v1 [P P P]                          ← 시작
시각 1:  RS-v1 [P P P]   RS-v2 [P]              ← 새 RS 생성, 1개 추가 (surge)
시각 2:  RS-v1 [P P]     RS-v2 [P P]            ← v2가 Ready 되면 v1 하나 제거
시각 3:  RS-v1 [P]       RS-v2 [P P P]
시각 4:  RS-v1 []        RS-v2 [P P P]          ← 완료. RS-v1은 0개로 "보존"됨
```

**RS-v1을 지우지 않고 0개로 남겨두는 이유** = 롤백. 롤백은 "RS-v1의 replicas를 다시 3으로" 올리는 것뿐입니다. `revisionHistoryLimit`(기본 10)개까지 옛 RS를 보관합니다.

### 2.2 속도/안전 조절 손잡이

```yaml
spec:
  strategy:
    type: RollingUpdate          # 또는 Recreate (전부 죽이고 새로 — 다운타임 있음)
    rollingUpdate:
      maxSurge: 25%              # 원하는 수보다 "추가로" 띄울 수 있는 양
      maxUnavailable: 25%        # 원하는 수에서 "부족해도 되는" 양
```

| 설정 | 효과 |
|------|------|
| `maxSurge: 1, maxUnavailable: 0` | 항상 정원 이상 유지 — 가장 안전, 자원 여유 필요 |
| `maxSurge: 0, maxUnavailable: 1` | 자원 추가 없이 교체 — 한 칸씩 줄었다 늘었습니다 |
| `Recreate` | 동시 실행되면 안 되는 앱(옛 버전과 DB 스키마 충돌 등) |

> **💡 "Ready"의 기준**: 새 Pod가 readiness probe(모듈 14)를 통과해야 "교체 1건 완료"로 칩니다. probe가 없으면 "프로세스 시작 = Ready"로 간주되어, **아직 초기화 중인 앱에 트래픽이 가는 사고**가 납니다. 롤링 업데이트의 무중단은 probe와 한 세트입니다.

### 2.3 리비전과 롤백

```bash
kubectl rollout history deployment/web          # 리비전 목록
kubectl rollout undo deployment/web             # 직전으로
kubectl rollout undo deployment/web --to-revision=2
```

주의: 롤백도 "새 롤링 업데이트"로 수행됩니다 (순간이동이 아님). 그리고 `kubectl apply`로 관리하는 팀에서 rollout undo를 쓰면 **Git의 선언과 클러스터 상태가 어긋납니다** — GitOps에서는 Git revert가 정석 (모듈 39).

## 3. 무엇이 업데이트를 트리거하는가

`spec.template`이 바뀔 때**만** 새 RS가 생깁니다. replicas 변경은 버전 교체가 아니므로 RS 재생성 없음.

같은 이유로 — `image: myapp:latest`를 다시 apply해도 **template이 동일하므로 아무 일도 안 일어납니다.** "분명 새 이미지 푸시했는데 배포가 안 돼요"의 단골 원인. 해결: 태그를 바꾸거나(`v1.2.3`), `kubectl rollout restart`(template에 재시작 annotation을 찍어 강제 트리거).

## 4. DaemonSet — 노드마다 1개

```yaml
kind: DaemonSet            # replicas 필드가 아예 없습니다
```

- 보장: **대상 노드마다 정확히 1개.** 노드 추가 → 자동 배치, 노드 제거 → 같이 소멸.
- 용도: 노드 단위 인프라 — 로그 수집기(fluent-bit), 모니터링 에이전트(node-exporter), CNI(aws-node), kube-proxy. 모듈 02에서 본 kube-system의 그 Pod들이 전부 DaemonSet입니다.
- `nodeSelector`/affinity로 일부 노드만 대상 가능 (예: GPU 노드에만).

## 5. 어떤 컨트롤러를 쓰나 — 선택표

| 워크로드 | 컨트롤러 | 모듈 |
|----------|----------|------|
| 무상태 서버 (웹/API) | **Deployment** | 여기 |
| 노드마다 1개 에이전트 | **DaemonSet** | 여기 |
| 고유 ID/디스크 필요 (DB, Kafka) | StatefulSet | 19 |
| 끝나면 되는 작업 | Job | 20 |
| 주기 작업 | CronJob | 20 |

## 6. 소스코드에서 확인하기

- Deployment의 롤링 업데이트 산수: `pkg/controller/deployment/rolling.go` — `reconcileNewReplicaSet`(새 RS 늘리기) / `reconcileOldReplicaSets`(옛 RS 줄이기) 두 함수가 위 타임라인 그대로입니다
- RS의 개수 맞추기: `pkg/controller/replicaset/replica_set.go` 의 `manageReplicas`

## 요약 카드

| 질문 | 답 |
|------|----|
| Deployment가 직접 만드는 것? | ReplicaSet (Pod가 아님) |
| RS가 자기 Pod를 아는 방법? | label selector (오직 라벨) |
| 롤링 업데이트의 실체? | 새 RS 늘리고 옛 RS 줄이기 |
| 옛 RS를 0개로 남기는 이유? | 롤백용 설계도 보관 |
| `:latest` 재배포가 안 먹는 이유? | template 불변 → 트리거 없음 |
| DaemonSet의 개수 결정자? | 노드 수 (replicas 없음) |
