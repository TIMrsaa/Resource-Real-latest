# 이론 — 컨테이너 보안 계층과 Pod Security Admission

> **🌱 17세 눈높이 비유: 호텔 객실의 보안 설계**
> 투숙객(컨테이너)이 악당일 수 있다는 전제로 호텔(노드)을 설계합니다:
> - **runAsNonRoot** = 마스터키를 애초에 안 줌
> - **capabilities drop** = 객실 비치 공구함에서 위험한 공구(특권) 회수 — 필요한 것만 개별 지급
> - **seccomp** = 객실 전화에서 걸 수 있는 번호 제한 (프런트/룸서비스만 — 시스템콜 필터)
> - **readOnlyRootFilesystem** = 객실 벽/가구에 손 못 대게 — 낙서(악성코드 설치)는 메모지(emptyDir)에만
> - **user namespaces** = 객실 안에선 "사장님"이어도 로비(호스트)에선 일반 투숙객 신분
> - **PSA** = 층(namespace)마다 붙는 보안 등급표 — "이 층은 restricted: 기준 미달 투숙객은 체크인 거부"

---

## 1. securityContext 핵심 필드 (Pod/컨테이너 레벨)

```yaml
spec:
  securityContext:                    # Pod 레벨 (공통)
    runAsNonRoot: true                # uid 0이면 기동 거부
    runAsUser: 10001
    runAsGroup: 10001
    fsGroup: 10001                    # 볼륨 파일의 그룹 소유권
    seccompProfile: { type: RuntimeDefault }   # 런타임 기본 시스템콜 필터
  containers:
  - name: app
    securityContext:                  # 컨테이너 레벨 (Pod 설정을 덮음)
      allowPrivilegeEscalation: false # setuid/파일 capability 통한 상승 차단
      readOnlyRootFilesystem: true    # / 를 읽기 전용으로
      capabilities:
        drop: ["ALL"]                 # 전부 회수 후
        # add: ["NET_BIND_SERVICE"]   # 꼭 필요한 것만 (1024 미만 포트 바인딩 등)
```

### capabilities — root 권한의 분해

리눅스는 "root의 전능"을 ~40개 조각(capability)으로 분해했습니다. 컨테이너 기본값도 십수 개를 가집니다 — 대부분 앱은 **하나도 필요 없습니다**:

| capability | 가능해지는 것 (= 공격자에게 주는 것) |
|------------|--------------------------------------|
| SYS_ADMIN | 마운트 등 — "사실상 root", 절대 금지급 |
| NET_RAW | raw 소켓 — ARP 스푸핑, 스니핑 |
| NET_ADMIN | 인터페이스/라우팅 조작 |
| SYS_PTRACE | 타 프로세스 메모리 열람 |
| NET_BIND_SERVICE | <1024 포트 바인딩 (정당한 용도가 흔한 예외) |

### seccomp — 시스템콜 화이트리스트

`RuntimeDefault` = containerd의 기본 프로파일 (위험 시스템콜 ~40개 차단: mount, reboot, kexec...). 비용 거의 0, 커널 취약점 공격면 대폭 축소 — **안 쓸 이유가 없습니다.** 더 조이려면 Localhost 타입 커스텀 프로파일(앱이 쓰는 콜만).

### privileged — 모든 것의 무효화

`privileged: true` = 격리 사실상 해제 (모든 caps + 장치 접근). CNI/CSI/모니터링 에이전트 같은 **노드 인프라 전용** — 일반 워크로드에 보이면 그 자체가 사고입니다.

## 2. Pod Security Admission (PSA)

PodSecurityPolicy(1.25 제거)의 후계 — **내장 admission**(웹훅 아님, 모듈 23의 분류로는 인프로세스).

### 3 표준 (Pod Security Standards)

| 수준 | 의미 | 대표 차단 항목 |
|------|------|----------------|
| privileged | 무제한 | — (시스템 ns용) |
| **baseline** | 알려진 상승 경로 차단 | privileged, hostPath, hostNetwork, 위험 caps |
| **restricted** | 현행 모범사례 강제 | baseline + runAsNonRoot, drop ALL, seccomp, allowPrivilegeEscalation:false |

### 3 모드 — ns 라벨로 적용

```bash
kubectl label ns prod \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted
```

- **enforce**: 위반 Pod 생성 거부
- **warn**: kubectl에 경고만 / **audit**: 감사 로그 기록만
- 위 조합이 운영 정석: "baseline은 강제, restricted는 경고로 준비" → 준비되면 enforce를 restricted로 승격 (모듈 23의 점진 도입과 동형)
- 버전 고정 가능: `enforce-version=v1.36` — 표준이 버전마다 강화되므로 업그레이드 시 갑작스런 거부 방지

### PSA의 한계 → 정책 엔진의 자리

PSA는 **고정된 3단계**뿐입니다. "우리 회사는 restricted + 이미지 레지스트리 제한 + 라벨 강제"같은 커스텀은 — ValidatingAdmissionPolicy(모듈 23)나 Kyverno/Gatekeeper(cncf 파트)로. PSA = 바닥, 정책 엔진 = 맞춤.

## 3. user namespaces — 마지막 퍼즐 (1.33 GA)

```yaml
spec:
  hostUsers: false      # 이 한 줄!
```

- 컨테이너의 uid 0(root)이 호스트의 **비특권 고유 uid**(예: 100000번대)로 매핑 — 모듈 01에서 소개한 USER namespace의 실전화
- 효과: 컨테이너 탈출에 성공해도 호스트에서는 일반 유저 — 탈출 피해의 핵심 차단
- "root가 필요해서 어쩔 수 없는" 레거시 이미지도 호스트 관점 비특권으로 돌릴 길이 열림
- 요건: 최신 런타임/커널 (EKS 1.36 AL2023 노드 OK), 일부 볼륨 타입과의 호환 확인

## 4. restricted 통과 모범 템플릿 (이 모듈의 산출물)

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    seccompProfile: { type: RuntimeDefault }
  automountServiceAccountToken: false        # 모듈 11
  containers:
  - name: app
    image: <digest 고정 권장>                 # 모듈 01
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities: { drop: ["ALL"] }
    volumeMounts:
    - { name: tmp, mountPath: /tmp }          # 쓰기 필요 경로는 emptyDir로
    resources: { requests: {...}, limits: {...} }   # 모듈 26 QoS
  volumes:
  - { name: tmp, emptyDir: {} }
```

## 5. 소스코드에서 확인하기

- PSA 본체: `staging/src/k8s.io/pod-security-admission/` — `policy/` 에 baseline/restricted의 체크 항목이 버전별 코드로
- 표준 문서: https://kubernetes.io/docs/concepts/security/pod-security-standards/

## 요약 카드

| 질문 | 답 |
|------|----|
| 일반 앱의 capabilities 정답? | drop ALL (+필요한 것만 add) |
| 거의 공짜인 보안 한 줄? | seccompProfile: RuntimeDefault |
| PSA 적용 방법? | ns 라벨 (enforce/warn/audit × 표준) |
| restricted의 핵심 요구? | nonRoot + drop ALL + seccomp + 상승 차단 |
| 탈출해도 일반 유저? | hostUsers: false (user namespaces) |
| PSA로 부족한 커스텀은? | VAP(CEL)/Kyverno/Gatekeeper |
