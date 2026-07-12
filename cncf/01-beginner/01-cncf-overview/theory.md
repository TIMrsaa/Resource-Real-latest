# 이론 — 재단 구조, 성숙도 사다리, 심사의 실체, landscape 읽는 법

> **🌱 17세 눈높이 비유: 프로 축구 리그 시스템**
> - **CNCF** = 축구협회 — 팀(프로젝트)을 직접 운영하지 않습니다. 리그 규칙을 정하고, 승격을 심사하고, 구단명과 엠블럼(상표)을 보호합니다
> - **Sandbox** = 유스 리그 — 들어오기 쉽습니다. "협회 소속"이지만 실력 보증은 아닙니다
> - **Incubating** = 2부 리그 — 실제 관중(프로덕션 사용자)이 있고 운영이 돌아간다는 심사를 통과
> - **Graduated** = 1부 리그 — 다회사 코칭진(유지보수자 다양성), 보안 감사, 검증된 흥행(채택)까지 심사 통과
> - **TOC** = 승격 심사위원회 — 기술 이사진. 각 분과 자문(TAG)의 도움을 받습니다
> - **왜 협회가 필요한가** = 구단주(회사)가 팀을 통째로 사유화해 "우리 팀 경기는 이제 유료 채널만"이라고 못 하게 — 엠블럼과 리그 자격은 협회 소유입니다
> - **landscape** = 리그 전체 선수 명감 — 포지션(카테고리)별로 전 팀이 실려 있습니다

---

## 1. 재단의 구조 — 누가 무엇을 결정하나

```
Linux Foundation
└── CNCF
    ├── Governing Board (GB)     회원사 대표 — 예산·마케팅·법무 (기술 결정 안 함!)
    ├── TOC                      기술 감독 위원회 — 프로젝트 승인·승격·아카이브 결정
    │   └── TAG (기술 자문 그룹)  분야별 자문·심사 실무 — 2025년 개편으로 5개 체제:
    │        Infrastructure / Workloads Foundation / Operational Resilience /
    │        Developer Experience / Security and Compliance
    ├── End User Community       사용 기업들 — 채택 검증의 출처 (졸업 심사의 "실명 관중")
    └── 프로젝트들 (각자 자체 거버넌스 — CNCF는 소유하되 지휘하지 않습니다)
```

핵심 분리 두 가지: ① **돈(GB)과 기술(TOC)의 분리** — 회원사가 돈으로 기술 결정을 살 수 없는 구조. ② **재단과 프로젝트의 분리** — CNCF는 상표·자산을 보유할 뿐, 각 프로젝트는 자체 유지보수자 거버넌스로 굴러갑니다(k8s의 SIG, argo의 proposal — cicd 27에서 본 그것).

## 2. 왜 재단인가 — 중립성의 세 기둥

| 기둥 | 내용 | 반례가 증명한 가치 |
|---|---|---|
| **상표·자산** | 이름·로고·도메인이 재단 소유 | NATS(2024): 원회사가 프로젝트 회수 시도 → 재단이 상표 보유라 실패, 프로젝트 잔류 |
| **라이선스** | Apache 2.0 고정 | 재단 밖: Terraform→BSL, Redis→SSPL 전환 — 사용자가 하루아침에 포크(OpenTofu/Valkey)로 이주 |
| **거버넌스** | 단일 벤더 지배 탈피 요구 | 한 회사의 피벗·매각·폐업이 프로젝트의 죽음이 되지 않게 |

기술 선택의 언어로 번역하면: **CNCF Graduated = "이 도구에 인생·회사를 걸어도 사유화·유료화·급사 리스크가 구조적으로 낮다"는 보험 증서**입니다. 성능·기능의 보증이 아니라는 점이 중요합니다(§4).

## 3. 성숙도 사다리 — 각 단계의 심사 실체

```
지원(Application) → Sandbox → Incubating → Graduated
                      │            │            └ 아카이브(Archived)로 내려가기도 (rkt처럼)
```

| | Sandbox | Incubating | Graduated |
|---|---|---|---|
| 심사 | TOC 투표(가벼움) | **실사(due diligence)** | 더 엄한 실사 |
| 요구 | 클라우드 네이티브 정합성, IP 이전 | 실 프로덕션 사용자(실명), 릴리스 프로세스, 기여자 흐름 | **다회사 유지보수자**, 거버넌스 문서, **보안 감사**(제3자), 채택 증명 |
| 신호 | "실험 — 재단이 지켜봄" | "실전 투입 사례 있음" | "산업 표준급 안정성·지속성" |
| 예 | 신생 다수 (부침 심함) | OpenTelemetry(최대 규모), Backstage, Crossplane, Strimzi | K8s, Prometheus, Envoy, Helm, Argo, Cilium, Istio, etcd... (~35개, 2026-06 기준) |

주의점 셋: ① Sandbox는 **품질 보증이 아닙니다** — 들어오기 쉽고 조용히 죽기도 합니다. ② Incubating에도 거대 프로젝트가 있습니다(OpenTelemetry는 K8s 다음 규모) — 단계≠크기. ③ Graduated도 영원하지 않습니다 — 활동이 죽으면 아카이브 논의가 열립니다.

## 4. 배지가 보증하지 않는 것 — 심사관의 눈

Graduated 배지가 말해주지 **않는** 것: 우리 요구에 맞는지(카테고리 내 선택은 48에서), 성능이 좋은지, 운영이 쉬운지, 우리 팀 스킬과 맞는지. 배지는 지속성 보험이지 적합성 판정이 아닙니다. 그래서 심사관의 눈을 직접 갖춰야 합니다:

```
① 유지보수자 다양성   한 회사가 커밋의 80%면 — 그 회사가 곧 프로젝트 (버스 팩터)
② 릴리스 리듬         정기 릴리스 + 보안 패치 속도 (CVE 대응 이력)
③ 채택의 실명성        ADOPTERS.md에 회사 이름이 실명으로 있는가
④ 거버넌스의 실재      GOVERNANCE.md가 실제로 작동한 흔적 (유지보수자 교체 이력 등)
⑤ 활동 추이           DevStats — 커밋·기여자·이슈 응답의 추세 (절대값보다 방향)
```

이 다섯을 확인하는 훈련이 lab-02입니다 — cicd 19에서 kaniko(아카이브)를 걸러낸 감각의 체계화이고, CNCF 밖 도구에도 그대로 적용됩니다.

## 5. landscape — 지도의 구조와 읽는 법

```
landscape.cncf.io — 카테고리 격자:
  Provisioning / Runtime / Orchestration & Management /
  App Definition & Development / Observability & Analysis / (+ Platform, Serverless...)
각 칸: 로고 하나 = 프로젝트 or 제품 — ★ CNCF 프로젝트가 아닌 것도 실려 있습니다!
  (회원사 제품·관련 오픈소스 포함 — "landscape에 있음" ≠ "CNCF 프로젝트")
데이터 원본: github.com/cncf/landscape 의 landscape.yml — lab-01에서 직접 집계
```

읽는 규율: **배지(성숙도)부터 확인** — 같은 칸의 로고들이 Graduated·Sandbox·상용 제품으로 뒤섞여 있습니다. 02~10의 지도 모듈들은 이 카테고리 축을 따라갑니다.

## 6. 프로젝트의 일생 — 들어옴부터 아카이브까지

```
기증(donation): 회사/개인이 IP·상표를 재단에 이전 — 이후 "되가져가기" 불가 (NATS의 교훈)
성장: Sandbox → (실사) → Incubating → (실사+감사) → Graduated
쇠퇴: 활동 감소 → TOC 검토 → Archived (rkt, Brigade 등) — 코드는 남지만 재단 지원 종료
분사·통합: 프로젝트 간 흡수, 서브프로젝트 독립 등 — 살아있는 생태계의 신진대사
```

아카이브는 실패 낙인이 아니라 **정직한 신호 체계**입니다 — 19의 kaniko처럼 조용히 방치되는 것보다, "더 이상 유지되지 않음"을 공식 선언하는 쪽이 사용자에게 안전합니다.

## 7. 소스/도구에서 확인하기

- TOC 저장소 (심사 기준·실사 문서의 원본): https://github.com/cncf/toc — `process/`
- 성숙도 정의: https://www.cncf.io/project-metrics (+ toc의 graduation criteria)
- landscape 데이터: https://github.com/cncf/landscape — `landscape.yml`
- DevStats (전 프로젝트 활동 통계): https://devstats.cncf.io
- 아카이브 목록: https://www.cncf.io/archived-projects/

## 요약 카드

| 질문 | 답 |
|------|----|
| CNCF의 본질 기여? | 코드가 아니라 **보험** — 상표·라이선스·거버넌스의 중립 보유 |
| 돈과 기술? | GB(예산)와 TOC(기술 결정)의 분리 — 회원비로 승격을 못 삽니다 |
| 3단계 신호? | Sandbox(실험·무보증) / Incubating(실전 사례) / Graduated(다회사+감사+채택) |
| 배지의 한계? | 지속성 보험이지 적합성·성능 판정이 아님 — 심사관의 눈 5종은 직접 |
| landscape 주의? | 로고 ≠ CNCF 프로젝트 (제품 혼재) — 배지부터 확인 |
| 아카이브? | 실패 낙인이 아니라 정직한 신호 — 방치보다 안전 (kaniko의 교훈) |
