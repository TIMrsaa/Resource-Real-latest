# 이론 — Pod, ReplicaSet, Deployment, Namespace

> **🌱 K8s 객체는 "회사 조직도" 다**
> Pod = 한 팀 (몇 명이 같이 일함), Deployment = "그 팀 항상 3개 유지" 라는 인사규정, Namespace = 부서, Service = 부서 대표 번호.
> 이름이 어렵게 들리지만 모두 "사람을 어떻게 묶고, 항상 자리에 있게 하고, 어떻게 부를지" 의 룰일 뿐.

> **💡 일상 비유로 이해하기**
> 
> Pod 는 **한 사무실에 같이 앉은 동료들**입니다. 같은 책상(IP/볼륨)을 공유하고, 회사가 사무실을 옮기면 다 같이 이동(=재시작) 합니다. 컨테이너 = 동료 1명, Pod = 사무실 단위. 그래서 K8s 는 Pod 단위로 스케줄링합니다.

## 1. Pod — Kubernetes의 최소 배포 단위

### 1.1 컨테이너와 Pod의 차이

Docker만 쓸 때는 "컨테이너 하나를 띄운다" 가 단위였습니다. K8s는 **Pod** 라는 한 단계 위 추상화를 단위로 씁니다.

```
+-------------------- Pod ----------------------+
|                                                |
|   +-------------+    +-------------------+    |
|   | container A |    | container B (sidecar) | |
|   +-------------+    +-------------------+    |
|                                                |
|   Shared:  ┌─ network namespace (같은 IP)      |
|            ├─ IPC namespace                    |
|            └─ Volumes                          |
+------------------------------------------------+
```

**Pod 안의 컨테이너들은:**
- 같은 IP를 공유 (서로 `localhost`로 호출 가능)
- 같은 볼륨을 마운트 가능
- 함께 스케줄링됨 (같은 노드에 배치)
- 함께 시작/종료됨

### 1.2 왜 Pod라는 추상화가 필요한가?

**시나리오**: 메인 앱 + 사이드카 (로그 수집기, 프록시 등)
- 메인 앱이 파일에 로그를 씀
- 사이드카가 그 파일을 읽어 외부로 전송
- 같은 호스트에 있어야 효율적, 같이 죽고 같이 살아야 일관성 유지

→ Pod라는 단위가 이런 상호 의존 컨테이너들을 묶기에 자연스럽다.

### 1.3 Pod 라이프사이클

```
Pending  →  Running  →  Succeeded
                    ↘  Failed
                    ↘  Unknown
```

- **Pending**: 노드에 스케줄링 대기, 또는 이미지 pull 중
- **Running**: 최소 1개 컨테이너가 실행 중
- **Succeeded**: 모든 컨테이너가 성공적으로 종료
- **Failed**: 어떤 컨테이너가 실패로 종료
- **Unknown**: 노드와 통신 불가

### 1.4 Pod는 단명(ephemeral)하다

Pod는 직접 만들 수 있지만, **거의 안 씁니다.** 노드 장애나 업데이트가 일어나면 그냥 사라집니다. 그래서 Pod의 복제본을 보장해주는 상위 컨트롤러가 필요합니다 → **ReplicaSet/Deployment**.

> **🧠 Pod 는 "소모품" 이라는 사고방식**
> 컨테이너 시절엔 "이 컨테이너 살리자" 였지만 K8s 에선 "이 Pod 가 죽어도 똑같은 Pod 를 다시 띄우면 됨" 이 표준이다.
> 그래서 Pod 에 *고유 ID* (DB connection, 로컬 디스크) 를 의존시키면 안 된다 — 그 역할은 StatefulSet/PVC 가 따로 맡는다.

---

## 2. ReplicaSet — 복제본 수 보장

ReplicaSet은 "Pod 3개 항상 떠 있어야 함"같은 **목표 상태**를 유지합니다.

```
ReplicaSet (replicas: 3)
   ├── Pod-abc (생성됨)
   ├── Pod-def (생성됨)
   └── Pod-ghi (생성됨)

[누가 Pod-def 죽임] → ReplicaSet이 새로 생성
   ├── Pod-abc
   ├── Pod-jkl  ← 새로 만든 거
   └── Pod-ghi
```

### 동작 원리

1. ReplicaSet은 `selector`로 자기가 관리할 Pod를 식별
2. 현재 Pod 수를 세어 `replicas` 와 비교
3. 부족하면 만들고, 많으면 삭제

### 실무에서 직접 쓰지는 않는다

ReplicaSet 위에 **Deployment** 가 있으니 직접 쓸 일은 거의 없습니다. 하지만 동작은 알아야 합니다 — Deployment가 만든 ReplicaSet이 고장 났을 때 디버깅하려면.

> **🧠 "selector 가 일치해야 자기 Pod 를 안다"**
> ReplicaSet 의 selector 와 Pod template 의 labels 가 어긋나면 컨트롤러는 자기가 만든 Pod 도 못 알아본다 → 무한히 새 Pod 생성.
> 디버깅 시 `kubectl get rs` → 이상한 ReplicaSet 가 보이면 selector/label mismatch 부터 의심.

---

## 3. Deployment — 실무 표준

Deployment는 ReplicaSet에 다음 기능을 더한 것:

- **롤링 업데이트** (점진적 교체)
- **롤백** (이전 버전으로 되돌리기)
- **버전 이력** 관리

### 3.1 롤링 업데이트 시나리오

```
초기 상태:  ReplicaSet-v1 [Pod, Pod, Pod]
            ┌──── 사용자 트래픽 ────┐

이미지 업데이트 (kubectl set image):
            ReplicaSet-v1 [Pod, Pod, Pod]   ← 줄어듦
            ReplicaSet-v2 [Pod]              ← 늘어남

진행:       ReplicaSet-v1 [Pod]
            ReplicaSet-v2 [Pod, Pod]

완료:       ReplicaSet-v1 []                 ← 0으로
            ReplicaSet-v2 [Pod, Pod, Pod]
```

이 과정 동안 사용자 트래픽은 끊기지 않습니다 (양쪽 ReplicaSet의 Pod가 동시에 살아있는 시점이 있음).

### 3.2 strategy 옵션

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 25%        # 평소 replicas의 25%까지 더 만들 수 있음
    maxUnavailable: 25%  # 평소 replicas의 25%까지 못 쓸 수 있음
```

`replicas: 4` 일 때 `maxSurge=25%, maxUnavailable=25%` →
- 동시에 살아있는 Pod 최대 5개 (4 + 1)
- 동시에 사용 가능한 Pod 최소 3개 (4 - 1)

### 3.3 롤백

```bash
kubectl rollout history deployment/my-app
kubectl rollout undo deployment/my-app                # 직전 리비전으로
kubectl rollout undo deployment/my-app --to-revision=2
```

내부적으로는 이전 ReplicaSet의 replicas를 늘리고 현재 ReplicaSet의 replicas를 줄이는 식으로 동작.

> **🧠 Deployment 는 "ReplicaSet 의 ReplicaSet" 이다**
> Deployment 가 새로 만드는 건 Pod 가 아니라 *새 ReplicaSet* 이다 — 그 ReplicaSet 이 Pod 를 만든다.
> 그래서 롤링 중엔 ReplicaSet 두 개가 동시 존재하고, 롤백 = 옛 ReplicaSet 의 replicas 만 늘리는 단순한 동작이다.

---

## 4. Namespace — 논리적 격리

### 4.1 개념

K8s 클러스터 안에서 리소스를 그룹화하는 가상 공간:

```
Cluster
├── Namespace: default        ← 명시 안하면 여기로
├── Namespace: kube-system    ← K8s 시스템 컴포넌트
├── Namespace: prod-app       ← 운영 앱
└── Namespace: dev-app        ← 개발 앱
```

### 4.2 격리되는 것 / 안 되는 것

**격리되는 것**:
- Pod, Deployment, Service, ConfigMap, Secret 등 대부분 객체
- 같은 이름을 다른 NS에 쓸 수 있음 (`prod-app/my-svc` ≠ `dev-app/my-svc`)
- RBAC, ResourceQuota, LimitRange가 NS 단위로 적용 가능

**격리 안 되는 것 (cluster-scoped)**:
- Node, PersistentVolume, StorageClass, ClusterRole, Namespace 자체

### 4.3 DNS

같은 NS의 Service는 짧은 이름으로:
```
http://my-svc/
```

다른 NS의 Service는 FQDN으로:
```
http://my-svc.other-namespace.svc.cluster.local/
```

### 4.4 사용 패턴

| 기준 | 분리 정책 |
|------|----------|
| 환경 | `prod` / `staging` / `dev` |
| 팀 | `team-a` / `team-b` |
| 시스템 | `kube-system` / `monitoring` / `karpenter` |
| 멀티테넌트 | 고객별 NS |

> **🧠 Namespace 는 보안 경계가 아니다**
> 같은 클러스터의 Pod 들은 NS 가 다르더라도 *기본적으로 서로 통신 가능* 하다.
> 진짜 격리는 NetworkPolicy + RBAC + ResourceQuota 를 함께 걸어야 완성 — NS 만 나눈 건 "이름 구분" 일 뿐.

---

## 5. 객체 간 관계 정리

```
Deployment
    └── (관리) ReplicaSet (현재/구 버전 모두 관리 가능)
                    └── (생성) Pod
                                └── (포함) Container(s)

         ↑ 모두 Namespace 안에 존재
```

**관리 흐름**:
- `Deployment` 의 `replicas`/이미지 변경 → ReplicaSet 갱신/생성
- ReplicaSet은 항상 `replicas` 수만큼 Pod 유지
- Pod는 컨테이너를 실제로 노드에 띄움

> **🧠 위→아래 한 방향 흐름만 기억하라**
> 위 객체는 아래 객체를 *생성/관리* 만 한다 — Pod 가 자기 Deployment 를 바꿀 수 없다.
> 그래서 "Pod 만 손으로 고쳤더니 컨트롤러가 다시 원복" 같은 현상은 정상 — manifest 는 위 객체부터 고쳐야 한다.

다음: [lab-01-pod.md](./lab-01-pod.md)

---

## 부록 A — 초보자용 비유 모음 (헷갈릴 때 이거)

### 🏨 호텔 비유

| K8s 개념 | 호텔 비유 |
|---------|----------|
| **Cluster** | 호텔 체인 전체 |
| **Node** | 호텔 건물 1동 |
| **Pod** | 객실 한 칸 (1팀이 들어감) |
| **Container** | 객실 안의 사람 1명 |
| **Deployment** | "객실 3개 항상 깨끗하게 유지해주세요" 매니저 |
| **Service** | 호텔 대표 전화번호 (방 번호 몰라도 연결됨) |
| **Ingress** | 호텔 1층 안내데스크 (외부 손님 → 적절한 방 안내) |
| **Namespace** | 호텔의 층 (1층=프론트, 2층=레스토랑) |
| **Label** | 객실 카드의 색깔 태그 (VIP, 흡연실 등) |
| **ConfigMap** | 객실의 안내책자 (설정값 모음) |
| **Secret** | 객실의 미니 금고 (비밀번호) |
| **PVC** | "냉장고 5L짜리 주세요" 주문서 |
| **PV** | 실제 냉장고 (객실에 설치됨) |

### 🎬 라이프사이클 영화

Pod의 인생을 영화로 보면:

```
Pending(대기실)        → "어느 노드가 받아줄까..."
ContainerCreating(분장실) → "이미지 다운로드 중..."
Running(무대)          → "일하는 중!"
Terminating(퇴장)      → "잘 가요"
Failed(NG)            → "다음 테이크!"
```

### 🎯 selector 와 labels 의 관계 (가장 헷갈리는 부분)

```
[Deployment]
  selector.matchLabels: { app: web }   ← "이런 라벨 가진 Pod는 내 거"
  template.metadata.labels: { app: web } ← "내가 만들 Pod엔 이 라벨 붙임"
                                         ↑ 두 값이 일치해야 자기가 만든 Pod를 못 알아봄
[Service]
  selector: { app: web }                ← "이런 라벨 가진 Pod로 트래픽 보냄"
```

**비유**: 직원에게 사원증을 만들어주고(label), 출입카드 시스템에 "이 사원증이면 통과" (selector) 를 등록하는 것.

---

## 부록 B — 자주 받는 질문 (FAQ)

### Q1. "Pod와 컨테이너의 차이를 솔직히 잘 모르겠어요"
대부분의 경우 **Pod 1개 = 컨테이너 1개** 라고 생각해도 됩니다. Pod가 따로 있는 이유는 "가끔 컨테이너 2~3개가 한 묶음으로 같이 살아야 할 때(사이드카)" 그 묶음을 표현하기 위해서입니다.

### Q2. "ReplicaSet을 직접 만들 일이 있나요?"
**거의 없음**. Deployment를 만들면 K8s가 알아서 ReplicaSet을 만들어줍니다. ReplicaSet 개념을 아는 이유는 디버깅할 때 (`kubectl get rs`) 뭐가 보이는지 이해하기 위해서.

### Q3. "Pod가 죽었는지 어떻게 알아요?"
```bash
kubectl get pods                  # STATUS와 RESTARTS 컬럼 보기
kubectl describe pod <name>       # Events 섹션의 Last 보기
kubectl logs <name> --previous    # 죽기 전 로그
```

### Q4. "롤링 업데이트 중에 사용자는 어떤 Pod를 받게 되나요?"
랜덤. 신/구 버전 Pod가 동시에 떠있는 시간이 있으므로, **앱이 하위 호환성을 가져야 무중단 가능**. 이게 깨지면 (DB 스키마 갑자기 바뀜 등) "롤링 중에만 에러"가 발생.

### Q5. "Namespace 분리가 보안 격리인가요?"
**아니오**. NetworkPolicy를 별도로 안 만들면 NS끼리 네트워크 통신이 가능합니다. NS는 "네임스페이스(이름 충돌 방지)" + RBAC 단위 + 청구/할당량 단위 로 이해하세요.

---

## 부록 C — 명령어 한 줄 요약

```bash
# 가장 많이 쓰는 5개
kubectl get pods                                  # 상태 보기
kubectl describe pod <name>                       # 디테일 + Events
kubectl logs <name> -f                            # 로그 따라가기
kubectl exec -it <name> -- sh                     # 안에 들어가기
kubectl apply -f file.yaml                        # 적용

# 자주 쓰는 디버깅
kubectl get events --sort-by='.lastTimestamp'     # 클러스터 이벤트 시간순
kubectl get pods -o wide                          # IP, Node 같이 보기
kubectl rollout status deploy/<name>              # 롤링 진행 상황
kubectl rollout undo deploy/<name>                # 직전 버전 되돌리기
```
