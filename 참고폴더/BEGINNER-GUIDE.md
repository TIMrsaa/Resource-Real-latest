# 초보자를 위한 입문 가이드 (Read Me First)

> 이 문서는 Kubernetes/EKS를 처음 만나는 분이 본 커리큘럼을 시작하기 전에 한 번 읽어보면 좋은 자료입니다.
> "이 단어가 뭐지?", "왜 이게 필요하지?" 같은 의문을 미리 풀어드립니다.

---

## 0. 학습을 시작하기 전 마음가짐

K8s는 **"한번에 다 이해할 수 없는 시스템"** 입니다.
- Pod → Service → Deployment → Ingress → Node → Cluster... 추상화 계층이 많음
- 처음엔 70%만 이해해도 충분. **손으로 직접 띄워봐야** 머리에 들어옵니다
- 막히면 [용어집](./reference/glossary.md)과 [치트시트](./reference/)를 먼저 보세요

---

## 1. 컨테이너 → Kubernetes 까지의 흐름

### 1.1 우리는 왜 컨테이너를 쓰는가?

```
[옛날]                          [Docker 이후]
서버 1대 = 앱 1개               서버 1대 = 컨테이너 N개
- 환경마다 동작이 다름           - "내 컴에선 됐는데" 사라짐
- 배포 = 쉘 스크립트              - 이미지 = 불변 빌드 산출물
- 의존성 충돌 (Python 2 vs 3)   - 격리된 파일/네트워크 NS
```

**컨테이너 = 코드 + 실행 환경(OS 라이브러리, 런타임)을 한 덩어리로 묶은 것**

### 1.2 컨테이너만으로 부족한 이유

서버 한 대에서 컨테이너 하나는 Docker로 충분합니다. 하지만 실서비스에서는:

| 문제 | 누가 해결? |
|------|----------|
| 컨테이너가 죽으면 누가 다시 띄우지? | 오케스트레이터 |
| 트래픽이 늘면 컨테이너 개수를 어떻게 늘리지? | 오케스트레이터 |
| 어떤 서버(노드)에 띄울지 누가 결정? | 오케스트레이터 |
| 서로 다른 컨테이너끼리 어떻게 통신? | 오케스트레이터 |
| 비밀번호/설정값을 어떻게 안전하게 주입? | 오케스트레이터 |
| 새 버전 배포 시 무중단으로 교체? | 오케스트레이터 |

→ 이 모든 일을 해주는 것이 **Kubernetes (K8s)**.

### 1.3 K8s를 한 줄로 정의하면

> **"수많은 컨테이너를 여러 서버에 걸쳐 자동으로 배치/복구/연결/확장해주는 시스템"**

---

## 2. K8s의 핵심 멘탈 모델 (이거 하나만 기억하세요)

### "원하는 상태(desired)"를 선언하면, K8s가 알아서 "현재 상태"를 그쪽으로 맞춘다

```
사용자: "Pod 3개를 항상 띄워둬" (선언)
   ↓
K8s 컨트롤 플레인: 현재 상태 확인 → 부족하면 만들고, 많으면 죽임 (조정)
   ↓
실제 노드: Pod 3개 실행 중
```

이걸 **선언형(declarative)** 이라고 부릅니다. 반대는 명령형(imperative): "Pod를 지금 만들어".

YAML 파일은 곧 **"내가 원하는 클러스터 상태의 명세서"** 입니다.

```yaml
kind: Deployment
spec:
  replicas: 3        # ← "복제본을 3개 유지하고 싶다" 라는 선언
```

K8s는 이걸 보고 1초마다 "지금 3개 떠있나?" 체크하고, 부족하면 만들고, 많으면 죽입니다. 이걸 **컨트롤 루프(control loop)** 라고 합니다.

---

## 3. K8s 클러스터 한 장 그림

```
┌──────────────────────── Kubernetes Cluster ────────────────────────┐
│                                                                    │
│  ┌────── Control Plane (관제탑) ──────┐                            │
│  │  • API Server  ← 모든 명령은 여기로 │                            │
│  │  • etcd        ← 모든 상태 DB       │                            │
│  │  • Scheduler   ← Pod를 어느 노드에  │                            │
│  │  • Controller  ← 조정 루프 실행     │                            │
│  └─────────────────────────────────────┘                            │
│                       ↕                                             │
│  ┌──── Node 1 ────┐  ┌──── Node 2 ────┐  ┌──── Node 3 ────┐        │
│  │  kubelet       │  │  kubelet       │  │  kubelet       │        │
│  │  kube-proxy    │  │  kube-proxy    │  │  kube-proxy    │        │
│  │  ┌────┐ ┌────┐ │  │  ┌────┐        │  │  ┌────┐ ┌────┐ │        │
│  │  │Pod │ │Pod │ │  │  │Pod │        │  │  │Pod │ │Pod │ │        │
│  │  └────┘ └────┘ │  │  └────┘        │  │  └────┘ └────┘ │        │
│  └────────────────┘  └────────────────┘  └────────────────┘        │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### 컴포넌트 역할 (외울 필요 없음, 그림만 머리에)

- **API Server**: 우리가 `kubectl` 로 보내는 모든 명령의 입구. REST API
- **etcd**: 키-값 데이터베이스. 클러스터의 모든 상태가 여기 저장됨
- **Scheduler**: "이 Pod는 어느 노드에 띄울까?" 결정
- **Controller Manager**: "원하는 상태 vs 현재 상태" 격차를 메우는 루프들의 모음
- **kubelet**: 각 노드의 에이전트. 실제로 컨테이너를 띄움
- **kube-proxy**: 노드의 네트워크 라우팅 담당

### EKS는 무엇이 다른가?

- AWS가 **Control Plane을 대신 운영**해줍니다 (관제탑이 AWS 소유)
- 우리는 **Node만 관리**하면 됨 (또는 Karpenter로 자동화)
- 비용: 클러스터당 시간당 약 $0.10 + EC2 비용

---

## 4. 이 커리큘럼에서 자주 나오는 객체 한눈에

| 객체 | 한 줄 설명 | 비유 |
|------|-----------|------|
| **Pod** | 컨테이너 1~N개의 묶음. 배포 최소 단위 | 게스트 1팀이 들어가는 호텔방 |
| **ReplicaSet** | "Pod N개 항상 떠있게 유지" | 식당에서 빈 테이블 N개 유지 |
| **Deployment** | ReplicaSet + 무중단 업데이트/롤백 | 메뉴 교체 가능한 식당 |
| **Service** | Pod 묶음으로의 안정적인 접근점(IP/이름) | 대표 전화번호 |
| **Ingress** | 외부 → Service 라우팅 (HTTP) | 건물 1층 안내데스크 |
| **ConfigMap** | 설정값을 외부화 | 환경 변수 모음집 |
| **Secret** | 비밀번호/토큰 (base64) | 금고 |
| **PV / PVC** | 영구 저장소 + 사용 신청서 | 창고 + 입주 신청서 |
| **StatefulSet** | 순서/이름이 중요한 Pod 모음 (DB 등) | 좌석 지정 콘서트 |
| **DaemonSet** | 모든 노드에 1개씩 띄우는 Pod | 층마다 1명씩 청소부 |
| **Job / CronJob** | 한번 실행 / 주기 실행 작업 | 일회용 알바 / 정기 청소 |
| **Namespace** | 객체들을 그룹화하는 가상 공간 | 사무실의 부서 칸막이 |
| **Node** | 컨테이너가 실제로 도는 서버(EC2) | 호텔 건물 한 동 |

---

## 5. YAML 읽는 법 (모든 매니페스트의 공통 골격)

```yaml
apiVersion: apps/v1        # 어느 버전의 API를 쓸지 (Deployment는 apps/v1)
kind: Deployment           # 만들 객체의 종류
metadata:                  # 메타데이터 (이름, 라벨, 네임스페이스)
  name: my-app             # 객체 이름 (NS 안에서 유일해야 함)
  labels:                  # 검색/그룹핑용 키-값 (필수 아님)
    app: my-app
spec:                      # 원하는 상태 명세 (이 객체의 본체)
  replicas: 3              # 위에서 본 "선언" 부분
  selector:                # 어떤 라벨의 Pod를 내가 관리할지
    matchLabels:
      app: my-app
  template:                # 새 Pod를 만들 때 쓸 템플릿
    metadata:
      labels:
        app: my-app        # 위 selector와 일치해야 함 (안 그러면 Pod를 만들어도 못 알아봄)
    spec:
      containers:          # Pod 안의 컨테이너들
        - name: web
          image: nginx:1.27
```

### YAML 들여쓰기 규칙
- **공백 2칸** (탭 금지)
- 같은 부모면 같은 들여쓰기
- 리스트는 `-` 로 시작
- 콜론 뒤엔 항상 공백 한 칸

### 자주 하는 실수 Top 5
1. 탭 사용 → `error converting YAML`
2. `selector.matchLabels` 와 `template.metadata.labels` 불일치 → Pod는 뜨는데 ReplicaSet이 못 알아봄
3. `image: nginx:latest` 사용 → 재배포 때 어떤 버전이 떴는지 알 수 없음
4. `resources` 미지정 → 한 Pod가 노드 자원을 다 먹어버림
5. `apiVersion` 오타 (`apps/v1` 을 `app/v1` 로) → 친절하지 않은 에러

---

## 6. kubectl 첫 30분 생존 가이드

```bash
# 0. 클러스터 연결 확인
kubectl version
kubectl cluster-info
kubectl get nodes                    # 노드 목록

# 1. 객체 목록 조회 (가장 많이 쓰는 명령)
kubectl get pods                     # 현재 NS의 Pod
kubectl get pods -A                  # 모든 NS
kubectl get pods -o wide             # IP, 노드 등 추가 정보
kubectl get deploy,svc,ingress       # 여러 종류 한번에
kubectl get pods -w                  # watch (변화 실시간)

# 2. 자세히 보기 (트러블슈팅의 시작)
kubectl describe pod my-pod          # 사람이 읽기 쉽게 + Events
kubectl get pod my-pod -o yaml       # 전체 YAML (status 포함)

# 3. 로그
kubectl logs my-pod                  # 컨테이너 로그
kubectl logs my-pod -f               # follow
kubectl logs my-pod --previous       # 죽은 직전 컨테이너 로그

# 4. 안에 들어가기
kubectl exec -it my-pod -- sh        # 셸 접속
kubectl exec my-pod -- env           # 한 명령만 실행

# 5. 외부에서 접근 테스트
kubectl port-forward svc/my-svc 8080:80   # 로컬 8080 → 클러스터 svc:80

# 6. 적용/삭제
kubectl apply -f file.yaml           # 적용 (없으면 생성, 있으면 업데이트)
kubectl delete -f file.yaml          # 삭제

# 7. 디버그 Pod 띄우기 (네트워크 테스트 등)
kubectl run -it --rm dbg --image=alpine -- sh
# 안에서: apk add curl bind-tools && curl http://my-svc/

# 8. 컨텍스트/네임스페이스
kubectl config get-contexts          # 어떤 클러스터에 연결됐나
kubectl config current-context
kubectl config set-context --current --namespace=my-ns   # 기본 NS 바꾸기
```

**팁: alias로 손가락 아끼기**
```bash
alias k=kubectl
alias kgp='kubectl get pods'
alias kdp='kubectl describe pod'
```

---

## 7. 트러블슈팅의 황금 흐름

문제가 생기면 항상 이 순서:

```
1. kubectl get <리소스>       → 상태가 Pending? CrashLoopBackOff? Running?
2. kubectl describe <리소스>  → Events 섹션을 가장 마지막부터 위로 읽기
3. kubectl logs <pod>         → 앱 로그 / 컨테이너 출력
4. kubectl logs <pod> --previous → 죽은 컨테이너의 마지막 유언
5. kubectl exec -it <pod> -- sh  → 안에 들어가서 직접 확인
```

**상태별 의미**:

| 상태 | 보통 원인 | 어디 봐야 |
|------|----------|----------|
| Pending | 노드 자원 부족 / 스케줄링 실패 | `describe` Events |
| ContainerCreating | 이미지 pull 중 / 볼륨 마운트 중 | `describe` Events |
| ImagePullBackOff | 이미지 이름 오타 / private registry 인증 실패 | `describe` Events |
| CrashLoopBackOff | 앱이 시작하자마자 죽음 | `logs --previous` |
| OOMKilled | 메모리 한도 초과 | `describe` (Last State) |
| Running but not Ready | readinessProbe 실패 | `describe` + `logs` |

---

## 8. 본 커리큘럼 학습 권장 순서

```
[필수]
00-prerequisites      ← AWS 계정, 도구 설치, 비용 알람 (꼭 먼저!)
   ↓
PART-1 (01~04)        ← 로컬에서 K8s 기초 (Minikube/Kind도 가능)
   ↓
PART-2 (05~09)        ← 실제 EKS 클러스터로 진입
   ↓
PART-3 (10~15)        ← Karpenter/KEDA로 자동 스케일링
   ↓
[선택]
PART-4 (16~18)        ← 운영, 장애, 비용, 업그레이드
PART-5 (19~23)        ← Prometheus/Grafana 심화
```

**막힐 때 보면 좋은 자료** (이 레포 안):
- [reference/glossary.md](./reference/glossary.md) — 용어 사전
- [reference/cheatsheet-kubectl.md](./reference/cheatsheet-kubectl.md) — kubectl 명령 모음
- [reference/cheatsheet-aws.md](./reference/cheatsheet-aws.md) — AWS CLI
- [reference/cheatsheet-eksctl.md](./reference/cheatsheet-eksctl.md) — eksctl
- 각 모듈의 `pitfalls.md` — 흔한 함정 미리 보기

---

## 9. 비용 잔존 사고 막는 3가지 습관

1. **실습 끝났으면 즉시** `cleanup.sh` 실행
2. 매일 자기 전 `kubectl get nodes` 로 EKS 노드가 살아있나 확인
3. AWS Cost Explorer 즐겨찾기 → 매일 1번씩 확인

> EKS Control Plane은 **클러스터를 켜둔 시간만큼 과금**됩니다. 안 쓰면 `eksctl delete cluster` 하세요.

---

좋습니다. 이제 [README.md](./README.md) 의 진도 체크리스트로 돌아가서 `00-prerequisites` 부터 시작하세요.
