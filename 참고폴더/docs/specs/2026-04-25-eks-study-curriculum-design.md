# EKS 학습 커리큘럼 설계 (Kubernetes + Karpenter + KEDA)

- **작성일**: 2026-04-25
- **대상 학습자**: finn (BMF, AWS/Terraform 익숙, K8s 입문자)
- **위치**: `/Users/finn/test/eks-study/`

## 1. 학습 목표

1. Kubernetes 핵심 개념을 단단히 이해한다 (Pod부터 RBAC까지).
2. AWS EKS를 실제로 구축/운영할 수 있다 (네트워킹, IAM, 스토리지, 관측).
3. Karpenter로 노드 오토스케일링을 비용 효율적으로 운영할 수 있다.
4. KEDA로 이벤트 기반 워크로드 스케일링을 설계/구현할 수 있다.
5. 위 모든 인프라를 Terraform 모듈로 IaC화할 수 있다.

## 2. 트랙 및 일정

| 파트 | 트랙 | 모듈 수 | 예상 기간 |
|------|------|---------|-----------|
| Part 1 | Kubernetes 기초 (입문) | 4 | 1.5~2주 |
| Part 2 | EKS 실무 | 5 | 2~3주 |
| Part 3 | Karpenter + KEDA (운영 심화) | 6 | 2~3주 |
| Part 4 | 운영/트러블슈팅 | 3 | 1~1.5주 |
| **합계** | | **18** | **6.5~9.5주** |

## 3. 환경 및 도구

- **AWS 계정**: 실제 계정 사용. 리전은 `ap-northeast-2`(서울) 권장.
- **로컬 도구**: `aws-cli`, `kubectl`, `eksctl`, `helm`, `terraform`, `k9s`, `stern`.
- **IaC 전략**: Mix
  - Part 1~2 초반: `eksctl` 빠르게 띄우고 컨셉 학습
  - Part 3 후반(15번 모듈): 동일 인프라를 Terraform 모듈로 재구성
- **언어**: 모든 자료는 한국어. 명령어/코드 주석은 영어.

## 4. 시나리오 애플리케이션

**컨셉**: MSA 시뮬레이션 — 주문/결제/유저/알림 마이크로서비스. 모두 **Go**로 구현.

```
scenarios/
├── order-service/         # Go + Gin, REST API (주문 생성/조회)
├── payment-service/       # Go + SQS consumer (KEDA 시연용 워커)
├── user-service/          # Go + gRPC (서비스 간 통신)
├── notification-service/  # Go + Kafka consumer (KEDA Kafka 트리거)
├── frontend/              # Go + html/template (간단한 SSR)
├── shared/                # 공통 라이브러리 (logger, tracing, config)
├── docker-compose.yml     # 로컬 검증
└── Makefile               # build/test/docker 일괄 명령
```

**Go 통일의 학습 효과**
- 멀티스테이지 Dockerfile + distroless/scratch 이미지로 작은 컨테이너 시연
- 빠른 시작 시간 → KEDA 스케일링 반응성 체감
- `prometheus/client_golang`으로 일관된 메트릭 노출
- HPA/Karpenter 메트릭 기반 스케일 시연 용이

**시나리오 앱 빌드 시점**
- `00-prerequisites/`에서 모든 Go 서비스의 초기 코드 + Dockerfile + ECR 푸시 스크립트 제공
- Part 1~2에서는 미리 빌드된 ECR 이미지를 그대로 사용
- Part 3 (KEDA) 단계에서 SQS/Kafka 핸들러 부분을 학습자가 직접 보강

## 5. 폴더 구조

```
/Users/finn/test/eks-study/
├── README.md                           # 전체 로드맵 + 진도 체크리스트 + 학습 가이드
├── 00-prerequisites/                   # AWS/도구 셋업, 비용 가드레일
│
├── PART-1-Kubernetes-Basics/
│   ├── 01-core-concepts/               # Pod, ReplicaSet, Deployment, namespace
│   ├── 02-services-networking/         # Service(ClusterIP/NodePort/LB), Ingress, DNS
│   ├── 03-config-storage/              # ConfigMap, Secret, PV/PVC, StatefulSet
│   └── 04-rbac-helm/                   # ServiceAccount, RBAC, Helm 차트 만들기
│
├── PART-2-EKS-Practice/
│   ├── 05-eks-cluster-eksctl/          # eksctl로 클러스터 생성, kubeconfig
│   ├── 06-vpc-cni-networking/          # VPC CNI, AWS Load Balancer Controller
│   ├── 07-storage-irsa/                # EBS CSI Driver, IRSA, Pod Identity
│   ├── 08-observability/               # CloudWatch Container Insights, kube-prometheus-stack
│   └── 09-msa-deploy/                  # 시나리오 MSA 앱 EKS에 배포
│
├── PART-3-Karpenter-KEDA/
│   ├── 10-karpenter-install/           # Karpenter 설치, NodePool, EC2NodeClass
│   ├── 11-karpenter-advanced/          # Spot, Disruption, Consolidation, 비용 최적화
│   ├── 12-keda-basics/                 # KEDA 설치, ScaledObject, ScaledJob
│   ├── 13-keda-event-driven/           # SQS 트리거, Kafka 트리거, Prometheus 트리거
│   ├── 14-karpenter-keda-combo/        # 큐 폭주 시 Pod 폭증 → 노드 자동 증설 시연
│   └── 15-terraform-iac/               # 클러스터+addon+Karpenter+KEDA Terraform 모듈화
│
├── PART-4-Operations/
│   ├── 16-troubleshooting/             # 장애 시나리오 7개 (CrashLoop, OOM, 네트워크 등)
│   ├── 17-cost-optimization/           # Cost Explorer, Karpenter Spot 비율, 우상향 진단
│   └── 18-upgrade-strategy/            # EKS/노드 그룹/addon 업그레이드 전략
│
├── scenarios/                          # MSA 시나리오 앱 소스 (Go)
│
├── docs/
│   ├── specs/                          # 본 설계 문서 등
│   └── diagrams/                       # 아키텍처 다이어그램 (PNG/SVG)
│
└── reference/
    ├── cheatsheet-kubectl.md
    ├── cheatsheet-eksctl.md
    ├── cheatsheet-helm.md
    ├── cost-guardrails.md              # 실습 비용 통제 가이드
    └── links.md                        # 공식 문서/블로그 링크
```

## 6. 모듈 표준 구성

각 모듈은 동일한 구조를 따른다:

```
NN-module-name/
├── README.md              # 모듈 개요, 학습 목표, 선행 지식, 소요 시간, 예상 비용
├── theory.md              # 이론 (개념, 동작 원리, ASCII 다이어그램)
├── lab-01-xxx.md          # 실습 1 (단계별 명령어 + 검증 방법 + 트러블슈팅)
├── lab-02-xxx.md          # 실습 2
├── quiz.md                # 학습 확인 문제 5~10개 + 정답
├── manifests/             # Kubernetes 매니페스트 YAML (또는 helm/, terraform/)
├── pitfalls.md            # 흔한 함정 5선
└── cleanup.sh             # 비용 절감 정리 스크립트
```

## 7. 핵심 설계 원칙

1. **비용 가드레일 우선**
   - 모든 실습 종료 시 `cleanup.sh` 필수 실행
   - 모듈 시작 시 "예상 비용" 명시 (예: t3.medium 2대 × 2시간 = 약 0.2 USD)
   - `00-prerequisites/`에 비용 알람(AWS Budgets) 설정 포함

2. **점진적 시나리오**
   - Part 2 모듈 09부터 같은 MSA 앱을 계속 발전시킴
   - 매번 처음부터 새로 만들지 않음 → 학습 누적 효과

3. **이론 ↔ 실습 1:1 매칭**
   - 각 lab은 theory.md의 특정 섹션을 검증/체험하는 형태
   - "이 실습으로 확인하는 이론: §2.3 Karpenter Disruption" 식으로 명시

4. **트러블슈팅 통합**
   - 각 모듈 끝 `pitfalls.md`에 흔한 함정 5선
   - Part 4의 16번 모듈은 종합 트러블슈팅 시나리오집

5. **Karpenter+KEDA 핵심 시연 (모듈 14)**
   - SQS에 메시지 1만 건 주입
   - KEDA가 payment-service Pod를 0 → 50개로 스케일
   - Karpenter가 spot 노드를 자동 추가
   - Grafana로 Pod/Node 수 그래프, AWS Cost Explorer로 비용 추이 확인

## 8. 실습 비용 통제

- **목표**: 전체 커리큘럼 비용 < 100 USD (한 달 학습 가정)
- **수단**:
  - 모든 EKS 클러스터는 학습 시간 외 `eksctl delete cluster` 또는 노드 그룹 desired=0
  - Spot 인스턴스 우선 사용 (Karpenter 학습 모듈에서 본격 도입)
  - AWS Budgets 알람: 월 50 USD 도달 시 이메일
  - `cleanup.sh`에 NLB/EBS/EIP 등 잔존 리소스 체크 포함

## 9. 학습 검증 방법

- **모듈 단위**: `quiz.md` 통과 + 실습 산출물 확인 (`kubectl get` 출력 캡처)
- **파트 단위**: 미니 프로젝트
  - Part 1 종료: 최소 EKS 클러스터(t3.small × 1)에 `order-service` 단일 배포 + Service/Ingress 노출
  - Part 2 종료: EKS에 MSA 4종 배포 + 모니터링 스택 구성
  - Part 3 종료: 부하 테스트로 Karpenter+KEDA 동작 확인 (Pod/Node 그래프 캡처)
  - Part 4 종료: 전체 인프라를 Terraform 1-command 배포로 재현

## 10. 산출물

전체 학습 종료 시 다음을 보유:
- 실행 가능한 Go 기반 MSA 앱
- EKS + Karpenter + KEDA를 IaC화한 Terraform 모듈
- 학습 노트 18개 (`theory.md`, `pitfalls.md`)
- 트러블슈팅 시나리오 7개의 해결 기록
- 본인 GitHub에 포트폴리오로 사용 가능

## 11. 비범위(Non-goals)

다음은 이 커리큘럼에서 다루지 않는다:
- Service Mesh (Istio, Linkerd) — 향후 별도 커리큘럼
- GitOps (ArgoCD, Flux) — 향후 별도 커리큘럼
- 멀티 클러스터/Federation
- AWS 외 K8s (GKE, AKS, on-prem)
- 자격증 시험(CKA/CKAD) 직접 대비 — 본 커리큘럼은 실무 운영 역량에 초점

## 12. 다음 단계

본 spec 승인 후, `writing-plans` 스킬로 18개 모듈을 어떤 순서/방법으로 작성할지 구현 계획을 수립한다.
