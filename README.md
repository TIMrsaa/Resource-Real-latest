# 클라우드 네이티브 마스터 커리큘럼 (K8s · EKS · CICD · CNCF · Observability)

> **목표**: 4개 분야를 "공부하는 사람"이 아니라 **"작동 원리를 전부 이해하고 업스트림 오픈소스에 기여하는 사람"** 이 되는 것.
> **언어**: 본문 한국어, 코드/명령/리소스명 영어
> **실습 환경**: 실제 AWS 계정 (`ap-northeast-2`) — 비용 가드레일 필수
> **기준 시점**: 2026년 6월 (아래 버전 기준표 참고)

---

## 버전 기준표 (모든 문서의 기준)

| 항목 | 버전 / 상태 | 비고 |
|------|-------------|------|
| Kubernetes | **v1.36** ("Haru", 2026-04-22 릴리스) | 업스트림 지원: 1.34 / 1.35 / 1.36 |
| Amazon EKS | **1.36까지 지원** | 표준지원 14개월 + 연장지원 12개월 |
| Helm | **v4 (4.1.x~4.2.x)** | v3는 2026-07 버그픽스 종료, 2026-11 보안픽스 종료 → **v4 기준으로 학습** |
| Gateway API | GA (Ingress의 후계자) | Ingress는 유지보수 모드 — 둘 다 다루되 Gateway API 우선 |
| CNCF Graduated | 약 35개 | 최신 합류: Dragonfly (2026-01) |
| AWS CodeCommit | **신규 가입 불가** | Git 호스팅은 GitHub/GitLab 기준, AWS Code 시리즈는 Pipeline/Build/Deploy 중심 |

> 각 파트 시작 시점에 해당 분야 버전을 재확인하고 이 표를 갱신합니다.

---

## 4개 파트 구성

| 파트 | 폴더 | 내용 | 분량(계획) | 상태 |
|------|------|------|-----------|------|
| Part 1 | [`k8s/`](./k8s/) | Kubernetes 완전정복 — 컨테이너 원리부터 소스코드 기여까지 | 45 모듈 | ✅ 완료 |
| Part 2 | [`eks/`](./eks/) | Amazon EKS 실전 — RPS 측정/트래픽 처리, Karpenter, vpc-cni 기여 | 29 모듈 | ✅ 완료 |
| Part 3 | [`cicd/`](./cicd/) | CI/CD 전체 생태계 — GitHub Actions, AWS Code 시리즈, GitOps 등 | 28 모듈 | ✅ 완료 |
| Part 4 | [`cncf/`](./cncf/) | CNCF 랜드스케이프 전체 — 200+ 프로젝트 전수 + Graduated 심층 | 50 모듈 | ✅ 완료 |
| Part 5 | [`observability/`](./observability/) | 옵저빌리티 실전 — 로그·메트릭·트레이스 파이프라인을 K8s·EKS·AWS에서 | 26 모듈 | ✅ 완료 |

### 권장 학습 순서

```
k8s (기초~고급) ──→ eks ──→ cicd ──→ cncf ──→ observability
       │                              ↑              │
       └── k8s 05-contributor 는 cncf 기여 트랙과 연결┴─ cncf 11~14(프로젝트 내부)와 상호 보완
```

k8s를 끝내야 나머지가 이해됩니다. eks는 k8s 위에, cicd는 eks 배포 대상 위에, cncf는 전부를 아우릅니다. observability는 cncf 11~14의 프로젝트 내부 지식 위에 **실무 파이프라인**(AWS 관리형 스택 포함)을 얹습니다.

---

## 난이도 체계 (모든 파트 공통)

| 단계 | 폴더 | 도달 목표 |
|------|------|----------|
| 초급 | `01-beginner/` | 개념을 비유로 이해하고, 기본 조작을 손으로 할 수 있습니다 |
| 중급 | `02-intermediate/` | 실무에서 쓰는 기능을 설계 의도까지 이해하고 조합할 수 있습니다 |
| 고급 | `03-advanced/` | 내부 동작 원리(소스 레벨)와 숨겨진 기능까지 압니다 |
| 실무 | `04-production/` | 운영 사고를 예방/대응하고 대규모 환경을 튜닝할 수 있습니다 |
| 기여자 | `05-contributor/` | 소스를 빌드하고, 코드 구조를 알고, 업스트림에 PR을 보냅니다 |

## 모듈 구성 (문서 4종 체계)

```
NN-topic-name/
├── README.md       # 개요, 학습 목표, 선행 지식, 소요 시간, 예상 비용
├── guide.md        # [학습 가이드] 무엇을 어떤 순서로 왜 배우는지
├── theory.md       # [이론서] 동작 원리 + 🌱 17세 눈높이 비유 + ASCII 다이어그램
├── lab-NN-*.md     # [핸즈온 가이드] 실제 명령 + 예상 출력 + 검증 + 트러블슈팅
├── manifests/      # YAML/코드 (모듈에 따라 code/, workflows/, terraform/)
├── pitfalls.md     # [실습 가이드] 흔한 함정 + 실무 사고 사례
├── quiz.md         # [실습 가이드] 자가 점검 문제 + 해설
└── cleanup.sh      # AWS 리소스 정리 (비용 발생 모듈만)
```

**모듈 진행 순서**: README → guide → theory → lab → quiz → pitfalls → cleanup

---

## 비용 가드레일 (반드시 지킬 것)

1. **실습 후 즉시 cleanup**: AWS 리소스를 만드는 모든 모듈에는 `cleanup.sh`가 있습니다. 실행하고 끝내라.
2. **AWS Budgets 알람**: 월 50 USD 알람 설정 (참고폴더 `00-prerequisites/scripts/setup-budget-alarm.sh` 재사용 가능)
3. **k8s 파트의 대부분 실습은 EKS 1개 클러스터를 공유**합니다 — 모듈마다 클러스터를 새로 만들지 말 것.
4. **Spot 우선**: 노드그룹은 가능하면 Spot으로.
5. 학습 안 하는 날은 클러스터 삭제 (eksctl로 30분이면 재생성 가능).

---

## 진도 현황

- [x] 마스터 골격 (이 문서 + 4파트 README)
- [x] **Part 1: k8s — 45 모듈 완료** ([체크리스트](./k8s/README.md))
- [x] **Part 2: eks — 29 모듈 완료** ([체크리스트](./eks/README.md))
- [x] **Part 3: cicd — 28 모듈 완료** ([체크리스트](./cicd/README.md))
- [x] **Part 4: cncf — 50 모듈 + reference 완료** ([체크리스트](./cncf/README.md))
- [x] **Part 5: observability — 26 모듈 + reference 완료** ([체크리스트](./observability/README.md))

> **전 파트(1~5) 완료.** 커리큘럼의 최종 과제는 cncf 50과 observability 26의 졸업 과제(첫 이슈·첫 재현·첫 PR)를 실제 생태계에서 수행하는 것 — 졸업장은 자격증이 아니라 기여 이력입니다.
