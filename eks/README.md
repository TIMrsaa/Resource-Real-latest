# Part 2 — Amazon EKS 실전 ✅ (29개 모듈 완료)

> **목표**: EKS를 "쓸 줄 아는" 수준이 아니라 VPC CNI의 IP 할당 로직, ALB의 RPS 한계, Karpenter의 노드 결정 알고리즘까지 이해하고 **고칠 수 있는** 것.
> **기준 버전**: EKS 1.36
> **선행**: [k8s 파트](../k8s/README.md) 초급~중급
> **종착지**: 27~29 — 사용자에서 기여자로 (이 커리큘럼의 목적)

---

## 이 파트의 서사

```
01~06  경계를 안다        "AWS는 어디까지 해주는가" — CP/노드/Fargate/Auto Mode
07~12  부품을 연다        CNI·ALB·IAM·CSI·애드온·관측 — EKS가 실제로 동작하는 방식
13~20  측정하고 조종한다   부하를 재고(13) 그 숫자로 트래픽·스케일·노드·네트워크를 튜닝
21~26  운영으로 산다      업그레이드·비용·멀티클러스터·DR·보안·진단 — 반복 가능한 절차
27~29  고친다             로드맵 이슈 → Karpenter PR → vpc-cni 코드
```

13(측정)이 척추입니다 — 이후 모든 주장이 숫자로 검증됩니다. 그리고 26(진단 카드)이 앞의 25개 모듈을 하나의 심문 순서로 수렴시킵니다.

---

## 진도 체크리스트

### 01-beginner — 초급 ✅
- [x] **01-eks-vs-self-managed** — 경계선(관리 영역 분담), 요금 구조, 지원 정책, 비용 워크시트
- [x] **02-eksctl-cluster** — ClusterConfig, CloudFormation, get-token 인증 경로, access entries
- [x] **03-console-cloudshell** — 콘솔 6탭/리소스 뷰 원리, CloudShell 비상 운영
- [x] **04-eks-auto-mode** — Auto Mode: 내장 Karpenter/NodePool, 내장 컨트롤러, 제약 실측
- [x] **05-managed-nodegroups** — 3층 해부(NG→ASG→EC2), AMI(AL2023/Bottlerocket), 풀 설계, 업데이트
- [x] **06-fargate** — Pod=VM 모델, 프로파일, 제약 부딪히기, 3자 결정표

### 02-intermediate — 중급 ✅
- [x] **07-vpc-cni-deep** — ENI/IP 할당 회계, warm pool, prefix delegation, ipamd
- [x] **08-alb-controller** — ALB/NLB, target-type ip vs instance, TargetGroupBinding, group.name
- [x] **09-irsa-pod-identity** — OIDC/STS 내부 동작, Pod Identity 마이그레이션, 최소권한
- [x] **10-storage-csi** — EBS/EFS/S3 CSI, 스냅샷, 볼륨 확장, AZ 고정의 함정
- [x] **11-eks-addons** — 관리형 애드온, SSA 필드 소유권, configuration-values, 버전 정책
- [x] **12-observability-aws** — Container Insights 애드온, 로그 파이프라인, Logs Insights/알람, 비용 통제

### 03-advanced — 고급 (측정과 조종) ✅
- [x] **13-load-testing-rps** — **이 파트의 척추**: k6/vegeta, p99, Little's Law, open vs closed, coordinated omission
- [x] **14-traffic-engineering** — idle timeout·LOR 알고리즘, 무중단 배포 4종 세트(오류 0 증명), NLB cross-zone
- [x] **15-custom-metrics-hpa** — Prometheus Adapter/KEDA, target 산정법(13의 무릎×0.7), scale-to-zero의 함정
- [x] **16-ip-exhaustion** — 소진 방정식(AZ별 min!), warm 튜닝, secondary CIDR/custom networking, IPv6
- [x] **17-karpenter-deep** — provisioning 파이프라인, consolidation(delete/replace), NodePool 설계, Spot
- [x] **18-network-deep** — 패킷 경로 실측(veth/host route), 검문소 3층, Flow Logs의 사각(NP 드롭)
- [x] **19-graviton-gpu** — exec format error, multi-arch, device plugin의 "등록", time-slicing vs MIG, Neuron
- [x] **20-service-mesh-eks** — App Mesh 종료의 교훈, Istio mTLS STRICT, 카나리아/fault/서킷브레이커

### 04-production — 실무 ✅
- [x] **21-upgrades-prod** — 버전 정책, insights 게이트, 노드 플릿 5전략, Blue/Green 실연
- [x] **22-cost-optimization** — 숨은 3대장(전송·NAT·관측), 고아 색출, requests 갭, OpenCost 쇼백
- [x] **23-multi-cluster** — fleet 표준화(vCluster 실습), kubefed의 교훈, 페일오버 모형, "8할은 데이터"
- [x] **24-disaster-recovery** — 재건 스택 4층, 격리 사다리, 크로스 리전 BSL, RTO 분해표
- [x] **25-security-prod** — 심층 방어 6관문, Secrets Manager CSI, GuardDuty, **IMDS hop limit=1**
- [x] **26-troubleshooting-eks** — 계층 심문법, EKS 10대 진단 카드, collect.sh, 온콜 리허설

### 05-contributor — 기여자 ✅
- [x] **27-containers-roadmap** — 세 개의 문(로드맵/오픈소스/업스트림), 좋은 이슈의 5부 구조, 기여 사다리
- [x] **28-karpenter-contrib** — 코어/프로바이더 2저장소, 로컬 디버그 실행, 테스트 우선, 첫 PR
- [x] **29-vpc-cni-contrib** — 두 바이너리 해부, 07·16·18의 코드 좌표, 관측성 기여

### reference ✅
- [x] [cheatsheet-eksctl.md](./reference/cheatsheet-eksctl.md) — 클러스터·노드그룹·권한·애드온
- [x] [cheatsheet-aws.md](./reference/cheatsheet-aws.md) — 진단 3종, 고아 사냥, 보안, 비용
- [x] [glossary.md](./reference/glossary.md) — 용어집 (⚖️ 헷갈리는 짝 표시)
- [x] [links.md](./reference/links.md) — 소스 코드 우선 1차 자료

---

## 모듈 간 의존 지도 (진단이 막힐 때 되돌아갈 곳)

| 증상 | 카드 | 배경 모듈 |
|------|------|----------|
| ContainerCreating 정지 | 26-①  | 07 · 16 |
| Pending / Insufficient | 26-② | 17 · 22 |
| AccessDenied | 26-③ | 09 |
| 502 / 503 | 26-④ | 08 · 14 |
| 노드 NotReady | 26-⑤ | 02 · 05 |
| 애드온 DEGRADED / 설정 원복 | 26-⑦ | 11 |
| 볼륨 attach 실패 | 26-⑧ | 10 |
| Pod 간 통신 불가 | 26-⑨ | 18 |
| 스케일 동결 | 26-⑩ | 15 · 17 |

## 공유 실습 환경

- 클러스터: `k8s-study` (ap-northeast-2)
- **비용 3대 사고**: Ingress(ALB) 방치 · GPU 노드그룹 방치 · 로그 그룹 무기한 보존
- 모든 모듈에 `cleanup.sh` — 랩 종료 시 필수. 22의 고아 사냥 스크립트를 월 1회

---

> **다음 파트**: [cicd](../cicd/README.md) — Code 시리즈·GitHub Actions·GitOps 파이프라인 / [cncf](../cncf/README.md) — 랜드스케이프 전면 실습
