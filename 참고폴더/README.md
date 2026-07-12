# EKS 학습 커리큘럼 (Kubernetes + Karpenter + KEDA)

> **학습자**: finn (BMF)
> **기간**: 약 6.5 ~ 9.5주
> **환경**: 실제 AWS 계정 (`ap-northeast-2`)
> **언어**: 모든 자료는 한국어, 코드/명령은 영어

---

> **🌱 처음 배우신다면**: [BEGINNER-GUIDE.md](./BEGINNER-GUIDE.md) 부터 읽고 시작하세요.
> K8s/컨테이너의 기본 개념, 멘탈 모델, kubectl 30분 생존 가이드, YAML 읽는 법까지 정리되어 있습니다.
>
> **🔍 모르는 단어가 나오면**: [reference/glossary.md](./reference/glossary.md) — 가나다순 용어 사전

## 학습 목표

1. Kubernetes 핵심 개념을 단단히 이해한다 (Pod부터 RBAC까지).
2. AWS EKS를 실제로 구축/운영할 수 있다 (네트워킹, IAM, 스토리지, 관측).
3. Karpenter로 노드 오토스케일링을 비용 효율적으로 운영할 수 있다.
4. KEDA로 이벤트 기반 워크로드 스케일링을 설계/구현할 수 있다.
5. 위 모든 인프라를 Terraform 모듈로 IaC화할 수 있다.

---

## 트랙 개요

| 파트 | 트랙 | 모듈 수 | 예상 기간 |
|------|------|---------|-----------|
| Part 1 | Kubernetes 기초 (입문) | 4 | 1.5~2주 |
| Part 2 | EKS 실무 | 5 | 2~3주 |
| Part 3 | Karpenter + KEDA (운영 심화) | 6 | 2~3주 |
| Part 4 | 운영/트러블슈팅 | 3 | 1~1.5주 |
| **합계** | | **18** | **6.5~9.5주** |

---

## 진도 체크리스트

### 사전 준비
- [ ] **00-prerequisites** — AWS 계정/도구/비용 가드레일/ECR 셋업

### Part 1: Kubernetes 기초
- [ ] **01-core-concepts** — Pod, ReplicaSet, Deployment, Namespace
- [ ] **02-services-networking** — Service(ClusterIP/NodePort/LB), Ingress, DNS
- [ ] **03-config-storage** — ConfigMap, Secret, PV/PVC, StatefulSet
- [ ] **04-rbac-helm** — ServiceAccount, RBAC, Helm 차트 만들기

### Part 2: EKS 실무
- [ ] **05-eks-cluster-eksctl** — eksctl로 클러스터 생성, kubeconfig
- [ ] **06-vpc-cni-networking** — VPC CNI, AWS Load Balancer Controller
- [ ] **07-storage-irsa** — EBS CSI Driver, IRSA, Pod Identity
- [ ] **08-observability** — CloudWatch Container Insights, kube-prometheus-stack
- [ ] **09-msa-deploy** — 시나리오 MSA 앱 EKS에 배포

### Part 3: Karpenter + KEDA
- [ ] **10-karpenter-install** — Karpenter 설치, NodePool, EC2NodeClass
- [ ] **11-karpenter-advanced** — Spot, Disruption, Consolidation, 비용 최적화
- [ ] **12-keda-basics** — KEDA 설치, ScaledObject, ScaledJob
- [ ] **13-keda-event-driven** — SQS 트리거, Kafka 트리거, Prometheus 트리거
- [ ] **14-karpenter-keda-combo** — 큐 폭주 → Pod 폭증 → 노드 자동 증설 시연
- [ ] **15-terraform-iac** — 클러스터+addon+Karpenter+KEDA Terraform 모듈화

### Part 4: 운영
- [ ] **16-troubleshooting** — 장애 시나리오 7개
- [ ] **17-cost-optimization** — Cost Explorer, Karpenter Spot 비율, 우상향 진단
- [ ] **18-upgrade-strategy** — EKS/노드 그룹/addon 업그레이드 전략

### Part 5: Observability 심화 (Prometheus + Grafana)
- [ ] **19-prometheus-deep-dive** — 아키텍처, TSDB, ServiceMonitor, federation
- [ ] **20-promql-mastery** — 4 메트릭 타입, RED/USE, recording rules
- [ ] **21-custom-metrics-go** — scenarios Go 앱에 RED 메트릭 직접 추가
- [ ] **22-grafana-advanced** — Variables, Provisioning, Grafana Alerting
- [ ] **23-production-observability** — HA, Thanos/AMP, SLO, Alertmanager routing

---

## 학습 방법

각 모듈은 동일한 구조를 따릅니다:

```
NN-module-name/
├── README.md       # 모듈 개요, 학습 목표, 선행 지식, 소요 시간, 예상 비용
├── theory.md       # 이론 (개념, 동작 원리, ASCII 다이어그램)
├── lab-NN-xxx.md   # 실습 (단계별 명령어 + 검증 + 트러블슈팅)
├── quiz.md         # 학습 확인 문제 5~10개 + 정답
├── manifests/      # K8s 매니페스트 / helm / terraform 코드
├── pitfalls.md     # 흔한 함정 5선
└── cleanup.sh      # 비용 절감 정리 스크립트
```

**진행 권장 순서** (모듈 내):

1. `README.md` 읽고 학습 목표/선행 지식 확인
2. `theory.md` 정독 — 개념을 머리에 넣기
3. `lab-*.md` 실습 — 손으로 직접 해보기
4. `quiz.md` 풀어보기 — 이해도 자가 점검
5. `pitfalls.md` 읽기 — 함정 미리 인지
6. `cleanup.sh` 실행 — 비용 잔존 방지

---

## 비용 가드레일 (반드시 지킬 것)

1. **실습 후 즉시 cleanup**: 모든 모듈은 `cleanup.sh` 실행으로 마무리
2. **Spot 우선**: Karpenter 학습부터는 Spot 인스턴스 활용
3. **AWS Budgets 50 USD 알람**: `00-prerequisites/scripts/setup-budget-alarm.sh` 로 설정

전체 학습 비용 목표: **< 100 USD/월**

---

## 폴더 구조

```
eks-study/
├── README.md                         # 이 문서
├── 00-prerequisites/                 # AWS/도구 셋업
├── PART-1-Kubernetes-Basics/         # 모듈 01~04
├── PART-2-EKS-Practice/              # 모듈 05~09
├── PART-3-Karpenter-KEDA/            # 모듈 10~15
├── PART-4-Operations/                # 모듈 16~18
├── PART-5-Observability-Advanced/    # 모듈 19~23 (Prometheus + Grafana 심화)
├── scenarios/                        # MSA 시나리오 앱 (Go)
│   ├── order-service/                # REST API
│   ├── payment-service/              # SQS Worker
│   ├── user-service/                 # gRPC
│   ├── notification-service/         # Kafka Worker
│   ├── frontend/                     # SSR 프론트
│   └── shared/                       # 공통 라이브러리
├── docs/
│   ├── specs/                        # 설계 문서
│   ├── plans/                        # 구현 플랜
│   └── diagrams/                     # 아키텍처 다이어그램
└── reference/                        # 치트시트 + 외부 링크
```

---

## 참고 자료

- 치트시트: [`reference/`](./reference/)
- 설계 문서: [`docs/specs/`](./docs/specs/)
- 외부 링크 모음: [`reference/links.md`](./reference/links.md)

---

## 커리큘럼 완성 상태

본 커리큘럼은 23개 모듈 전체 (P0 기반 + P1 + P2 + P3 + P4 + P5) 가 작성되었습니다.

| Part | 모듈 수 | 상태 |
|------|---------|------|
| P0 — 기반 | 1 (00-prerequisites) + scenarios + reference | ✅ |
| P1 — Kubernetes 기초 | 4 (01~04) | ✅ |
| P2 — EKS 실무 | 5 (05~09) | ✅ |
| P3 — Karpenter + KEDA | 6 (10~15) | ✅ |
| P4 — 운영 | 3 (16~18) | ✅ |
| P5 — Observability 심화 | 5 (19~23) | ✅ |
| **합계** | **23 모듈** | |

학습은 위 진도 체크리스트의 모듈을 차례로 진행하시면 됩니다. 비용 가드레일 잊지 마세요.
