# 이론 — 보안 시간선, 정책 엔진 2강, 신원 두 축, 런타임 탐지, 전수 지도

> **🌱 17세 눈높이 비유: 콘서트장 보안**
> - **빌드 전(공급망)** = 티켓 발권 — 위조 못 하게 홀로그램(서명), 누가 언제 발권했는지 기록(provenance)
> - **배포 시점(admission)** = 입구 검문 — 티켓·소지품 검사, 규정 위반이면 **입장 거부**(예방)
> - **런타임(Falco)** = 장내 CCTV — 입장한 사람이 갑자기 무대로 뛰어들면 **경보**(탐지). 검문을 통과한 후의 돌발은 여기서만 잡힙니다
> - **신원(cert-manager/SPIFFE)** = 신분 확인 체계 — 스태프 목걸이(인증서), "이 사람이 진짜 스태프인가"(워크로드 아이덴티티). 신원이 없으면 검문도 CCTV도 "누구"를 몰라 무력
> - **정책 엔진(OPA/Kyverno)** = 규정집과 심판 — 검문 기준을 코드로. 규정이 없으면 검문관마다 제멋대로

---

## 1. 시간선 — 방어의 좌표축

| 시간대 | 방어 | 막는 것 | 못 막는 것 | 대표 |
|---|---|---|---|---|
| 빌드 전 | 서명·SBOM·provenance | 위조·변조·불명 출처 | 빌드 중 주입(SolarWinds) | cosign, in-toto, SBOM(cicd 21) |
| 배포 시점 | admission 검증·정책 | 미서명·정책위반 배포 | 통과 후의 행위 | OPA/Gatekeeper, Kyverno |
| 실행 중 | 런타임 탐지 | 이상 행위(셸 실행·권한 상승) | 탐지일 뿐 예방 아님 | Falco |
| (관통) 신원 | 인증서·워크로드 ID | 사칭·평문·만료 | — | cert-manager, SPIFFE/SPIRE |

핵심 명제: **각 층은 자기 시간대만 방어합니다**(cicd 21의 "서명이 못 막는 것"의 일반화). admission이 통과시킨 정상 이미지가 런타임에 익스플로잇당하면 — Falco만 그것을 봅니다. 방어는 층의 합이 아니라 곱이고, 지도의 가치는 우리 스택에서 빈 시간대를 드러내는 것.

## 2. 전수 지도 — 시간선에 배치 (기준 시점 2026-06)

### 정책 엔진 (관통 — CI·admission 양쪽)

| 프로젝트 | 성숙도 | 한 줄 |
|---|---|---|
| **OPA (Open Policy Agent)** | Graduated | 범용 정책 엔진 — rego 언어. K8s(Gatekeeper)·CI(conftest — cicd 24)·앱 인가까지 |
| **Kyverno** | Graduated | **K8s 네이티브** 정책 — YAML로 정책, CRD로 동작. 서명 검증(verifyImages) 내장 (심층 32) |

### 공급망 (빌드 전 — cicd 21의 좌표화)

| 프로젝트 | 성숙도 | 한 줄 |
|---|---|---|
| **sigstore** (cosign/Fulcio/Rekor) | (OpenSSF/LF) | keyless 서명·투명성 로그 — cicd 21의 그 도구 |
| **in-toto** | Graduated | 공급망 각 단계의 증명 연쇄 — SLSA provenance의 이론적 뿌리 |
| **The Update Framework (TUF)** | Graduated | 저장소 업데이트의 신뢰 모델 — Notary/레지스트리 서명의 기반 |
| **Notary / notation** | (일부 CNCF) | 레지스트리 아티팩트 서명 |

### 신원 (관통)

| 프로젝트 | 성숙도 | 한 줄 |
|---|---|---|
| **cert-manager** | Graduated | 인증서 자동 발급·갱신(Let's Encrypt·내부 CA) — TLS 만료 사고의 종결자 (심층 19) |
| **SPIFFE / SPIRE** | Graduated | 워크로드 아이덴티티 — "이 워크로드가 정말 X인가"를 검증 가능한 SVID로 (심층 33) |

### 런타임·탐지

| 프로젝트 | 성숙도 | 한 줄 |
|---|---|---|
| **Falco** | Graduated | 런타임 위협 탐지 — 시스템콜(eBPF/커널 모듈)을 규칙으로 감시 (심층 30) |
| **Tetragon** | (Cilium 일부) | eBPF 기반 런타임 관찰·강제 — Falco의 이웃/경쟁 |
| KubeArmor 등 | Sandbox~ | LSM 기반 런타임 강제 |

### 스캐너·기타

```
Trivy (Aqua — 비CNCF지만 사실상 표준) — 이미지·IaC·시크릿 스캐너
Clair — 이미지 취약점 스캔 (Quay 계열)
kube-bench / kube-hunter — CIS 벤치마크·침투 (Aqua)
Harbor (Graduated) — 레지스트리인데 서명·스캔·정책 내장 → 보안 접점 (심층 34, 09 지도에도)
external-secrets / SOPS / sealed-secrets (cicd 22) — 시크릿, 이 지도의 이웃
```

## 3. 정책 엔진 2강 — 설계 철학의 차이

| | OPA / Gatekeeper | Kyverno |
|---|---|---|
| 정책 언어 | **rego** (전용 언어 — 학습 곡선) | **YAML/CRD** (K8s 사용자에 친숙) |
| 적용 범위 | 범용 — K8s, CI(conftest), 앱 인가, Terraform | K8s 전용 (admission·generate·mutate) |
| 강점 | 한 언어로 조직 전체 정책, 복잡 로직 | 진입 쉬움, K8s 리소스 생성·변형까지 |
| 자리 | 다영역 정책 통일이 목표일 때 | K8s 정책만 필요·팀이 rego 부담일 때 |

cicd 24에서 conftest(OPA)로 파이프라인 YAML을 검사했고, cicd 21에서 Kyverno(verifyImages)로 서명을 강제했습니다 — **같은 "정책"이 도구에 따라 rego냐 CRD냐, CI냐 admission이냐로 갈립니다**. 둘은 경쟁이자 상호보완(OPA로 다영역 + Kyverno로 K8s 편의).

## 4. 신원의 두 축 — 무엇을 증명하나

```
cert-manager: "이 엔드포인트의 TLS 인증서" — 발급·갱신·회전 자동화
              해결하는 고통: 인증서 만료로 인한 새벽 장애(수동 갱신의 종말)
              Issuer(Let's Encrypt/Vault/내부 CA) → Certificate → Secret → 워크로드

SPIFFE/SPIRE: "이 워크로드가 누구인가" — SVID(검증 가능한 신원 문서)
              해결하는 고통: 서비스 간 "상대가 진짜인가"를 IP·네트워크가 아닌 암호학으로
              메시 mTLS(eks 20)·제로트러스트의 신원 뿌리 — 노드·워크로드 증명(attestation)
```

둘의 관계: cert-manager는 **인증서라는 물건**을, SPIFFE는 **워크로드의 신원**을 다룹니다 — 겹치기도(SPIRE가 인증서를 발급) 하지만 초점이 다릅니다. cicd 전체의 "비밀번호→신원" 서사의 인프라 계층.

## 5. 예방 vs 탐지 — Falco가 다른 이유

```
admission(Kyverno/OPA): 배포 게이트 — "나쁜 것을 못 들어오게"(예방). 통과 후는 안 봄
Falco(런타임):          실행 감시 — "들어온 것이 나빠지면 알아채게"(탐지). 시스템콜 기반
왜 둘 다: 정상 이미지가 통과 후 공격당함(0-day, 탈취된 자격증명, 컨테이너 탈출 시도)
         → admission은 이미 통과시켰습니다 → Falco의 규칙("컨테이너에서 셸 실행", 
           "/etc/shadow 읽기", "예상 밖 네트워크 연결")이 그 순간을 잡습니다
한계: Falco는 탐지·경보이지 차단이 아닙니다(대응은 별도 — 알림→자동 격리 등)
```

이것이 시간선 축의 실전 결론: **admission으로 예방하고 Falco로 탐지합니다** — 하나는 문지기, 하나는 CCTV, 둘 다 없으면 각자의 시간대가 사각입니다.

## 6. 소스/도구에서 확인하기

- OPA/Gatekeeper: https://www.openpolicyagent.org / Kyverno: https://kyverno.io (cicd 21·24 복습)
- cert-manager: https://cert-manager.io / SPIFFE: https://spiffe.io
- Falco: https://falco.org — 규칙 문법 / Tetragon: https://tetragon.io
- in-toto/TUF: https://in-toto.io / https://theupdateframework.io
- 성숙도 재확인: lab-01 (landscape.yml)

## 요약 카드

| 질문 | 답 |
|------|----|
| 지도의 축? | 수명주기 시간선 — 빌드전/배포시점/런타임 + 관통(신원·정책) |
| 각 층의 한계? | 자기 시간대만 방어 — admission 통과 후는 Falco만, 방어는 층의 곱 |
| 정책 2강? | OPA(rego·범용·CI+admission) vs Kyverno(YAML·K8s 네이티브·서명 검증 내장) |
| 신원 두 축? | cert-manager(인증서 물건) vs SPIFFE/SPIRE(워크로드 신원) |
| 예방 vs 탐지? | admission(못 들어오게) vs Falco(들어온 것이 나빠지면 경보) — 둘 다 필요 |
| 이미 아는 것? | cosign·OPA·Kyverno(cicd 21·24)의 좌표화 + 새 주민 Falco·cert-manager·SPIFFE |
