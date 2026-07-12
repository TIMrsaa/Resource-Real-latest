# 이론 — ARC의 구조, ephemeral의 필연성, 신뢰 경계

> **🌱 17세 눈높이 비유: 호텔 방 vs 기숙사 방**
> - **GitHub-hosted 러너** = 호텔: 체크아웃하면 청소가 들어오고, 다음 손님은 **완전히 새 방**을 받습니다. 앞사람의 물건도 지문도 없습니다
> - **EC2에 직접 설치한 러너** = 기숙사 방을 여러 명이 돌아가며 쓰기: 앞사람의 짐(설치된 툴), 낙서(환경변수), 그리고 **책상 서랍에 두고 간 열쇠**(자격증명)가 다음 사람에게 보입니다
> - **ARC의 ephemeral 러너** = 매번 새 방을 짓고 부수기: 호텔의 보장을 우리 건물에서 재현
> - **퍼블릭 저장소 + self-hosted** = 우리 기숙사 방을 **길에서 만난 사람에게** 하룻밤 빌려주기. 그 방은 우리 건물 안에 있고, 복도는 우리 금고로 이어집니다
> - **Karpenter와의 결합** = 손님이 몰리면 건물을 더 짓고, 비면 허뭅니다

---

## 1. self-hosted의 거래

| | GitHub-hosted | self-hosted |
|---|---|---|
| 격리 | 잡마다 새 VM (보장됨) | **우리가 만들어야 함** (ephemeral) |
| 네트워크 | 공용 인터넷 | VPC 내부 접근 가능 ← 주된 이유 |
| 하드웨어 | 고정 스펙 | 임의(GPU, 32vCPU, ARM) |
| 비용 | 분당 과금 | 인프라 비용 (스팟이면 저렴) |
| 패치·운영 | GitHub | **우리** |
| 신뢰 경계 | 외부 | **우리 VPC 안** ← 주된 위험 |

주된 이유와 주된 위험이 **같은 줄**에 있다는 것이 이 기술의 본질입니다: 러너가 우리 네트워크 안에 있습니다.

## 2. ARC 구조 (gha-runner-scale-set)

```
┌─ arc-systems 네임스페이스 ────────────────────────┐
│  gha-runner-scale-set-controller (Deployment)     │
│    - AutoscalingRunnerSet CRD를 watch             │
│    - GitHub API로 "대기 중인 잡"을 구독            │
└───────────────────────────────────────────────────┘
              │ 잡 감지 → 러너 Pod 생성
              ▼
┌─ arc-runners 네임스페이스 ────────────────────────┐
│  AutoscalingRunnerSet (CRD)                       │
│    ├ EphemeralRunner Pod #1  ← 잡 하나 실행 후 소멸│
│    ├ EphemeralRunner Pod #2                       │
│    └ (listener Pod: 잡 큐를 롱폴링)                │
└───────────────────────────────────────────────────┘
              │ Pod가 노드를 요구
              ▼
        Karpenter (eks 17) → 노드 생성/회수
```

핵심 성질:

- **잡 1개 = Pod 1개 = 러너 등록 1회.** 잡이 끝나면 러너는 GitHub에서 등록 해제되고 Pod는 삭제됩니다
- 컨트롤러는 GitHub App(또는 PAT)으로 인증 — App 권장(권한 범위·감사)
- `runs-on: <scale-set-name>` 으로 워크플로가 이 러너를 지목합니다

### 두 가지 실행 모드

| 모드 | 컨테이너 빌드 | 격리 |
|------|-------------|------|
| **kubernetes 모드** | 잡의 각 스텝을 별도 Pod로(hook) | 강함, 설정 복잡 |
| **dind (docker-in-docker)** | 러너 Pod 안에 Docker 데몬 사이드카 | 간단, **privileged 필요** |

dind가 흔하지만 privileged 컨테이너는 노드 탈출 위험(eks 25 관문 ③)을 안습니다. 대안: BuildKit을 rootless로, 또는 `buildkitd`를 별도 서비스로 두고 러너는 클라이언트만.

## 3. ephemeral이 협상 불가능한 이유

persistent(재사용) 러너에서 잡 A가 남긴 것:

```
~/.docker/config.json          ← 레지스트리 자격증명
~/.aws/credentials             ← 이전 잡의 임시 자격증명
/tmp/*, 설치된 전역 패키지      ← 다음 잡의 빌드에 섞임
백그라운드 프로세스             ← 다음 잡을 감시·조작 가능
git 저장소 캐시                 ← 소스 오염
```

잡 B가 다른 팀의 것이라면 — B가 A의 자격증명을 읽습니다. 같은 팀이어도 "왜 로컬에선 되는데 CI에서만"의 원인이 여기서 나옵니다.

ARC의 기본은 ephemeral이며, **`--once`/ephemeral 등록**으로 러너가 잡 하나만 처리하고 종료합니다. persistent로 되돌리는 설정은 존재하지만, 그것은 위 목록을 수용하겠다는 선언입니다.

## 4. 스케일링 — Karpenter와의 이중 자동화

```
잡 대기(GitHub 큐) → ARC가 러너 Pod 생성 → Pod Pending(노드 부족)
                                          → Karpenter가 노드 생성 (eks 17)
잡 종료 → Pod 삭제 → 노드 유휴 → consolidation으로 회수
```

튜닝 포인트:

- `minRunners`: 0이면 콜드 스타트(노드 생성 ~1분 + 이미지 pull). 지연에 민감하면 1~2를 상시
- 러너 이미지 크기가 곧 콜드 스타트 시간(04의 이미지 다이어트가 여기서 회수)
- Karpenter NodePool에 CI 전용 taint + spot 우선 (중단돼도 잡 재시도 가능하면)
- `do-not-disrupt`: 긴 잡이 consolidation에 희생되지 않게 (eks 17 pitfall 3)

## 5. 퍼블릭 저장소 + self-hosted = 금지

포크 PR의 워크플로는 **PR 작성자가 작성한 코드**를 실행합니다. 그 러너가 우리 VPC 안에 있다면:

```
1. 공격자가 포크에서 PR을 엽니다 (누구나 가능)
2. 워크플로가 우리 러너 Pod에서 실행됩니다
3. 그 Pod에서: VPC 내부 스캔, 메타데이터 서비스 접근(eks 25!), 
   Pod Identity 토큰 탈취, 클러스터 API 접근 시도
```

`pull_request`가 시크릿을 안 준다는 보호(03)는 **네트워크 위치를 보호하지 않습니다.** 방어:

- 퍼블릭 저장소에는 GitHub-hosted 러너만
- 프라이빗 저장소라도: 포크 PR 승인 필요 설정, 러너 Pod에 NetworkPolicy(기본 거부), IMDS hop limit=1(eks 25), Pod Identity 최소권한
- 러너 노드를 별도 서브넷·별도 SG로 격리

## 6. 러너의 IAM — 두 층

```
① 러너 Pod 자신의 권한 (Pod Identity — eks 09)
   → 최소: ECR pull, 로그 쓰기. 여기에 배포 권한을 주면 안 됩니다
② 워크플로가 assume하는 역할 (OIDC — 07)
   → 배포 권한은 여기에. sub 조건으로 저장소·브랜치·환경 통제
```

**핵심 규율**: 러너 Pod의 역할(①)에 배포 권한을 붙이면 — 그 러너에서 도는 **모든 워크플로**가 그 권한을 갖습니다(07의 조건 통제가 무의미해집니다). 러너는 "실행 환경"일 뿐 "권한 주체"가 아니어야 합니다.

## 7. 소스/도구에서 확인하기

- ARC(gha-runner-scale-set): https://github.com/actions/actions-runner-controller
- 러너 자체: https://github.com/actions/runner (26에서 기여)
- GitHub 문서: "Self-hosted runner security" — 퍼블릭 저장소 경고의 원문
- 대안: Philips labs terraform-aws-github-runner(EC2 기반 ephemeral)

## 요약 카드

| 질문 | 답 |
|------|----|
| self-hosted의 정당한 이유? | VPC 접근 / 특수 하드웨어 / 대규모 비용 / 규제 |
| 같은 줄에 있는 위험? | 러너가 **우리 네트워크 안**에 있습니다 |
| ARC의 단위? | 잡 1개 = ephemeral 러너 Pod 1개 |
| persistent 러너가 남기는 것? | 자격증명·설치물·프로세스 → 다음 잡이 읽습니다 |
| dind의 대가? | privileged — 노드 탈출 위험. rootless BuildKit 검토 |
| 절대 금지? | **퍼블릭 저장소 + self-hosted** (포크 PR이 VPC 안에서 실행) |
| 러너 Pod의 IAM? | 최소(ECR pull)만. 배포 권한은 워크플로의 OIDC 역할(07)로 |
