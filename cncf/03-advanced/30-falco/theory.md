# 이론 — 아키텍처, 시스템콜 소스, 규칙 언어, 대응, 비교

> **🌱 17세 눈높이 비유: 건물 전체의 행동 감지 CCTV**
> - **admission(07)** = 정문 검색대 — 들어올 때 검사(예방). 통과 후는 안 봅니다
> - **Falco** = 건물 안 모든 복도의 행동 감지 CCTV — "화장실에서 금고를 열려는 사람" 같은 이상 행동을 실시간 감지
> - **시스템콜** = 사람의 모든 행동(문 열기·물건 집기·전화 걸기) — CCTV는 이 행동들을 봅니다
> - **규칙** = "이상 행동"의 정의 — "직원 구역에 외부인이 들어가면 경보"처럼 미리 정한 것만 잡습니다
> - **한계** = CCTV는 경보를 울릴 뿐 도둑을 막지 않습니다(탐지≠예방). 그리고 규칙에 없는 새로운 수법은 못 잡습니다
> - **대응** = 경보 → 경비 출동(알림→격리). 경보만 울리고 아무도 안 오면 무의미

---

## 1. 아키텍처

```
시스템콜 소스(드라이버) → 룰 엔진 → 출력
     │                        │            │
  eBPF/커널모듈          규칙 대조     stdout/JSON
  (커널에서 syscall     priority별    → Falcosidekick
   이벤트 스트림)        조건 평가       → Slack/webhook/자동화

Falco 컴포넌트(K8s):
  falco (DaemonSet)      각 노드에서 시스템콜 감시 + 규칙 평가
  falcoctl               규칙·플러그인 관리
  falcosidekick          출력을 여러 대상으로 팬아웃(알림·대응)
  k8s-metacollector      K8s 메타데이터 부착(어느 Pod·네임스페이스)
```

## 2. 시스템콜 소스 — 드라이버의 진화

```
① 커널 모듈 (초기):
   커널에 모듈 로드 → 시스템콜 후킹
   위험: 커널 크래시 가능, 이식성 낮음(커널별 빌드), 서명 문제

② eBPF (현재 권장 — 22의 그것):
   modern_ebpf: CO-RE(Compile Once Run Everywhere), 커널 5.8+
   legacy ebpf: 구 커널
   → 검증기가 안전 보장(22), 커널 크래시 없음, 이식성

무엇을 보나:
  execve   (프로세스 생성 — "컨테이너 내 셸")
  open/openat (파일 접근 — "/etc/shadow", 토큰 경로)
  connect  (네트워크 — 예상 밖 아웃바운드)
  ptrace, setuid, mount, ... (권한 상승·탈출 시도)
  ★ 시스템콜은 컨테이너가 무엇을 하든 결국 거치는 지점 (03)
```

## 3. 규칙 언어 — 무엇을 이상으로 볼지

```yaml
- rule: Terminal shell in container
  desc: A shell was spawned in a container
  condition: >
    spawned_process and container
    and shell_procs and proc.tty != 0
    and container_entrypoint
  output: >
    Shell spawned in container
    (user=%user.name container=%container.name
     proc=%proc.cmdline parent=%proc.pname)
  priority: NOTICE
  tags: [container, shell, mitre_execution]
```

```
구성 요소:
  condition:  불리언 식 (시스템콜 필드로) — 무엇이 이상인가
  output:     경보 메시지 (필드 치환: %container.name, %proc.cmdline...)
  priority:   EMERGENCY~DEBUG (심각도)
  tags:       분류 (MITRE ATT&CK 매핑 등)

재사용:
  macro:  조건 조각 (spawned_process = evt.type in (execve,execveat) and evt.dir=<)
  list:   값 목록 (shell_binaries = [bash, sh, zsh, ...])
  → 규칙을 조합 가능하게 (20의 CoreDNS 플러그인, 23의 필터 체인과 같은 조립)

기본 규칙셋:
  Falco가 제공하는 수십 개 (MITRE ATT&CK 기반)
  falco_rules.yaml(핵심) + falco-incubating/sandbox(실험적)
```

## 4. 튜닝 — 오탐과의 싸움

```
문제: 기본 규칙이 정상 동작을 이상으로 잡습니다(오탐)
  예: 정상 배포 스크립트가 셸을 씁니다, 모니터링 에이전트가 /proc를 읽습니다
  → 오탐이 많으면 경보 피로 → 아무도 안 봅니다(07 사고의 다른 형태)

튜닝 방법:
  exceptions: 규칙에 예외 추가 (특정 프로세스·이미지는 제외)
  override: 기본 규칙을 커스터마이징
  우선순위 조정: 노이즈 규칙의 priority 하향 또는 비활성

★ 관측(06)의 알림 설계와 같은 원리:
  심각도 = 영향 × 긴급도, 오탐률 관리, 대응 가능한 경보만
  튜닝 없는 Falco = 노이즈 발생기
```

## 5. 대응 — 경보를 액션으로 (Falcosidekick)

```
Falco 출력 → Falcosidekick → 여러 대상:
  알림: Slack, Teams, PagerDuty, email
  저장: Elasticsearch, Loki(14), S3
  메트릭: Prometheus(11)
  ★ 자동 대응: Falcosidekick-UI + Response Engine
     경보 → 함수(FaaS)·워크플로 → 자동 격리(NetworkPolicy 주입·Pod 삭제·격리)

대응 설계 (07의 시간선 완성):
  탐지(Falco) → 트리아지(심각도) → 대응(알림·격리) → 사후(포스트모템)
  ★ 자동 격리는 신중히: 오탐 시 정상 워크로드를 죽일 수 있습니다
     (예방 아닌 탐지의 자동 대응은 오탐 비용이 큽니다)
```

## 6. 비교 — Falco vs Tetragon vs 강제

| | Falco | Tetragon(22) | seccomp/AppArmor |
|---|---|---|---|
| 방식 | eBPF/모듈 시스템콜 감시 | eBPF 시스템콜 감시+강제 | 커널 LSM/필터 |
| 성격 | **탐지**(경보) | 관찰+**강제**(차단) | **예방**(시스템콜 제한) |
| 규칙 | 풍부한 규칙 생태계 | TracingPolicy | 프로파일(허용 시스템콜) |
| 07 시간선 | 실행 중(탐지) | 실행 중(탐지+강제) | 실행 중(예방) |
| 자리 | 위협 탐지 표준 | Cilium 스택 통합 | 시스템콜 자체 제한 |

```
조합:
  예방: seccomp 프로파일로 불필요 시스템콜 차단(공격 표면 축소)
  탐지: Falco로 이상 행위 경보
  강제: Tetragon/KubeArmor로 특정 행위 실시간 차단
  → 셋은 대체가 아니라 다층 (07의 "층의 곱")
```

## 7. 소스/도구에서 확인하기

- Falco: https://falco.org/docs — rules, fields, drivers
- 규칙 필드: https://falco.org/docs/reference/rules/supported-fields/
- Falcosidekick: https://github.com/falcosecurity/falcosidekick
- 22(eBPF/Tetragon)·07(시간선)·06(알림 설계) 복습

## 요약 카드

| 질문 | 답 |
|------|----|
| Falco의 자리? | 07 시간선의 실행 중(탐지) — admission이 못 보는 통과 후 침해 |
| 어떻게 보나요? | 시스템콜 스트림을 eBPF/커널모듈로 가로채 규칙과 대조 |
| 드라이버 진화? | 커널 모듈(위험) → eBPF(안전, 22의 검증기) |
| 규칙 구성? | condition(이상 정의)/output/priority/tags + macro·list 조립 |
| 근본 한계? | 탐지지 예방 아님(이미 일어남), 규칙 밖은 못 봄 |
| 튜닝? | 오탐 관리 — 없으면 노이즈 발생기(06의 알림 설계) |
| 대응? | Falcosidekick → 알림·자동 격리 (경보만 쌓으면 무의미) |
| 비교? | Falco(탐지) / Tetragon(강제) / seccomp(예방) — 다층 |
