# 이론 — 기능 카탈로그: 신무기와 묻힌 보석 (v1.36 기준)

> **🌱 17세 눈높이 비유: 게임의 패치 노트와 히든 콘텐츠**
> K8s는 분기마다 패치(마이너 버전)가 나오는 게임입니다. **feature gate**는 "베타 서버에서만 켜진 실험 기능" 스위치고, Alpha→Beta→GA는 실험 → 공개 베타 → 정식 출시입니다.
> 고인물과 뉴비의 차이는 스펙이 아니라 **패치 노트를 읽는 습관**입니다.

---

## 0. Feature Gate 체계 30초 정리

| 단계 | 기본값 | 의미 |
|------|--------|------|
| Alpha | off | 실험 — 버그/제거 가능, 직접 켜야 함 (EKS 불가) |
| Beta | (1.24+부터 대부분) off→기능별 | API는 안정권, 세부 변경 가능 |
| GA/Stable | **on (게이트 제거)** | 정식 — 영구 보장 |

기능의 이력서 = KEP 번호. 예: sidecar = KEP-753 — 검색하면 8년치 토론이 나옵니다.

---

## 1부. 신무기 (최근 GA — 모르면 손해)

### 1.1 In-place Pod Resize (1.33 GA 경로) — 재시작 없는 리소스 변경

```bash
kubectl patch pod my-pod --subresource=resize --type=merge \
  -p '{"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"500m"}}}]}}'
```

- Pod **재시작 없이** CPU/메모리 requests/limits 변경 — cgroup 값을 라이브로 갱신 (모듈 01의 그 파일!)
- `resizePolicy`로 컨테이너별 "재시작 필요 여부" 선언 가능 (JVM 힙처럼 재시작이 필요한 경우)
- 의미: VPA의 최대 약점(재시작)이 사라지는 길 — rightsizing의 미래

### 1.2 네이티브 Sidecar (1.33 GA) — 이미 모듈 03에서 정복

`initContainers + restartPolicy: Always`. 복습 포인트: 시작은 앱보다 먼저, 종료는 나중, Job과도 호환.

### 1.3 Job 정밀 제어 세트

- **podFailurePolicy** (1.31 GA): exit code별 분기 — "코드 42는 재시도 무의미 → 즉시 실패", "노드 축출은 backoffLimit 카운트 제외"
- **successPolicy** (1.33 GA): Indexed Job에서 "리더 인덱스(0)만 성공하면 전체 성공" 같은 조건
- **backoffLimitPerIndex**: 인덱스별 독립 재시도 한도

### 1.4 PodDisruptionConditions / 명시적 종료 사유

Pod status의 `DisruptionTarget` condition — "왜 죽었나"(eviction? 선점? 노드 정리?)가 기계가 읽을 수 있게 기록됩니다. 모듈 26의 "Evicted vs OOMKilled" 구분이 API로 표준화된 것.

### 1.5 Dynamic Resource Allocation (DRA) — GPU의 미래 (1.34 GA 경로)

- device plugin의 후계자: GPU/가속기를 **PVC처럼** 신청(ResourceClaim)하는 모델
- `resourceClaims` + DeviceClass — 공유/분할/토폴로지 인지 할당
- AI 워크로드 시대의 핵심 — eks 파트 19(GPU)에서 실전

### 1.6 ValidatingAdmissionPolicy(CEL) — 모듈 23에서 정복. MutatingAdmissionPolicy가 후속으로 성숙 중

### 1.7 그 외 최근 세대 한 줄씩

| 기능 | 한 줄 |
|------|-------|
| Pod Scheduling Readiness (`schedulingGates`) | "준비될 때까지 스케줄링 보류" — 외부 시스템이 게이트 해제 (배치 오케스트레이터용) |
| matchLabelKeys (topologySpread) | 롤링 업데이트 중 신구 RS를 분리 계산 — spread 왜곡 해결 |
| Image Volume (베타 경로) | 이미지를 볼륨으로 마운트 — 모델/데이터를 OCI로 배포 |
| user namespaces (1.33 GA 경로) | 컨테이너 root ≠ 호스트 root — 모듈 01 USER ns의 실전화 (모듈 32) |
| kubectl debug --profile | sysadmin/general 등 디버그 권한 프리셋 |

---

## 2부. 묻힌 보석 (오래됐지만 모르는 사람이 많은)

### 2.1 Downward API — Pod가 자기 자신을 아는 법

```yaml
env:
- name: POD_NAME
  valueFrom: { fieldRef: { fieldPath: metadata.name } }
- name: NODE_NAME
  valueFrom: { fieldRef: { fieldPath: spec.nodeName } }
- name: CPU_LIMIT
  valueFrom: { resourceFieldRef: { resource: limits.cpu } }
```

로그에 Pod/노드 이름 박기, 런타임 스레드 수를 CPU limit에 맞추기 — 외부 조회 없이. (모듈 04 DaemonSet에서 한 번 썼습니다)

### 2.2 projected volume — 여러 소스를 한 디렉터리에

ConfigMap+Secret+Downward+SA토큰을 **하나의 마운트**로 합성. 특히 `serviceAccountToken` projection은 **audience/만료 지정 커스텀 토큰** — 외부 시스템(Vault, AWS)과의 연동 토대 (IRSA의 원리!).

### 2.3 EmptyDir의 옵션들

`medium: Memory`(tmpfs — 모듈 07 Secret이 쓰는 그것), `sizeLimit: 1Gi`(초과 시 Pod eviction — 모듈 26 사고사례의 해법).

### 2.4 Pod 간 리소스 공유 보석들

- `shareProcessNamespace: true`: Pod 내 컨테이너끼리 PID 공유 — 사이드카가 앱 프로세스에 시그널 가능
- `enableServiceLinks: false`: 레거시 env 주입(서비스마다 *_SERVICE_HOST) 끄기 — env 오염과 기동 지연 방지

### 2.5 Service/네트워크 보석들

- **Topology Aware Routing** (`service.kubernetes.io/topology-mode: Auto`): 같은 AZ 백엔드 우선 — **AZ 간 데이터 전송 비용 절감** (EKS에서 실질 비용 임팩트!)
- `internalTrafficPolicy: Local`: 클러스터 내부 트래픽도 같은 노드 우선
- Service `appProtocol`: L7 프로토콜 힌트 (LB 컨트롤러/메시가 활용)
- headless + `publishNotReadyAddresses`: 준비 안 된 멤버도 DNS에 (클러스터 부트스트랩용)

### 2.6 스케줄링/수명주기 보석들

- `terminationMessagePolicy: FallbackToLogsOnError`: 종료 메시지가 없으면 **마지막 로그 80줄을 status에** — `kubectl describe`만으로 사인 확인
- `activeDeadlineSeconds` (Pod에도 있습니다): 디버그 Pod 자동 소멸
- PriorityClass `preemptionPolicy: Never` (모듈 12) — 새치기 없는 VIP
- `kubectl events --watch --types=Warning`: Warning만 실시간 — 미니 관제

### 2.7 kubectl 보석들 (모듈 10 보강)

```bash
kubectl get pods --show-managed-fields -o yaml   # SSA 소유권 장부 (기본 숨김!)
kubectl diff -f x.yaml --server-side             # SSA 기준 diff
kubectl wait --for=jsonpath='{.status.phase}'=Running pod/x
kubectl create token <sa> --duration=10m         # SA 단기 토큰 즉석 발급
kubectl auth whoami
kubectl debug node/<n> --profile=sysadmin
kubectl apply --prune                            # (주의해서) 삭제까지 동기화
```

## 3. 소스코드에서 확인하기

- feature gate 전체 목록의 원본: `pkg/features/kube_features.go` — 한 파일에 모든 게이트와 단계가 주석과 함께
- KEP 디렉터리: https://github.com/kubernetes/enhancements/tree/master/keps — 번호로 검색

## 요약 카드

| 질문 | 답 |
|------|----|
| 기능 발굴 루틴? | 릴리스 블로그 → 게이트 표 → KEP → explain |
| EKS에서 쓸 수 있는 단계? | GA(+기본 on Beta) — Alpha는 kind에서 |
| 재시작 없는 리소스 변경? | in-place resize (`--subresource=resize`) |
| AZ 비용 절감 한 줄? | topology-mode: Auto annotation |
| 죽은 원인을 describe에서? | FallbackToLogsOnError + DisruptionTarget |
| GPU 할당의 미래? | DRA (ResourceClaim 모델) |
