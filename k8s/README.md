# Part 1 — Kubernetes 완전정복

> **목표**: 컨테이너가 도는 리눅스 커널 원리부터 kubernetes/kubernetes 소스코드에 PR을 보내는 것까지.
> **기준 버전**: Kubernetes **v1.36** (2026-04 릴리스, 지원 버전: 1.34/1.35/1.36)
> **실습 환경**: 실제 AWS EKS (`ap-northeast-2`) + 로컬 kind(기여자 트랙)
> **처음이라면**: [00-BEGINNER-GUIDE.md](./00-BEGINNER-GUIDE.md) 부터.

---

## 트랙 개요

| 레벨 | 폴더 | 모듈 수 | 도달 목표 |
|------|------|---------|----------|
| 초급 | `01-beginner/` | 10 | K8s의 모든 기본 객체를 손으로 다룹니다 |
| 중급 | `02-intermediate/` | 10 | 실무 기능(보안/스케줄링/오토스케일링/패키징)을 설계합니다 |
| 고급 | `03-advanced/` | 12 | 컴포넌트 내부 동작과 숨겨진 기능을 소스 레벨로 압니다 |
| 실무 | `04-production/` | 8 | 운영 사고 예방/대응, 대규모 튜닝, 자격증 |
| 기여자 | `05-contributor/` | 5 | K8s를 빌드하고 업스트림에 기여합니다 |

---

## 진도 체크리스트 (= 작성 현황)

### 01-beginner — 초급 ✅ (작성 완료)

- [x] **01-container-fundamentals** — 컨테이너의 정체: 리눅스 namespace, cgroup, OCI, 이미지 레이어
- [x] **02-k8s-architecture** — 클러스터 큰그림: control plane vs node, 선언적 API, 조정 루프
- [x] **03-pod** — Pod 해부: 컨테이너 묶음, pause 컨테이너, 라이프사이클, init/sidecar
- [x] **04-workloads** — Deployment/ReplicaSet/롤링업데이트/롤백/DaemonSet
- [x] **05-service** — Service 4종(ClusterIP/NodePort/LoadBalancer/ExternalName), Endpoints/EndpointSlice
- [x] **06-ingress-gateway** — Ingress(유지보수 모드)와 Gateway API(현재 표준) 비교 실습
- [x] **07-config-secret** — ConfigMap, Secret, 환경변수 vs 볼륨 마운트, 불변 ConfigMap
- [x] **08-storage-basics** — Volume, PV/PVC, StorageClass, 동적 프로비저닝
- [x] **09-namespace-labels** — Namespace, Label/Selector, Annotation, field selector
- [x] **10-kubectl-mastery** — kubectl 완전정복: explain, jsonpath, diff, patch, debug 입문

### 02-intermediate — 중급 ✅ (작성 완료)

- [x] **11-auth-rbac** — 인증(인증서/토큰/OIDC/IAM), 인가(RBAC), ServiceAccount, EKS access entries
- [x] **12-scheduling** — nodeSelector, affinity/anti-affinity, taint/toleration, topology spread, priority/preemption
- [x] **13-autoscaling** — HPA(v2 behavior), VPA, 메트릭 파이프라인(metrics-server)
- [x] **14-probes-lifecycle** — liveness/readiness/startup probe, lifecycle hook, graceful shutdown
- [x] **15-networkpolicy** — NetworkPolicy 설계 패턴, 기본 거부, egress 제어, VPC CNI 집행
- [x] **16-coredns** — 클러스터 DNS 동작 원리, Corefile, ndots 문제, 디버깅 루틴
- [x] **17-helm-deep** — Helm v4 기준: 차트 작성, 템플릿 함수, 의존성, hooks, OCI 배포
- [x] **18-kustomize** — base/overlay, patch 전략, 해시 제너레이터, Helm과의 조합
- [x] **19-statefulset** — StatefulSet, Headless Service, 순서 보장, PVC 템플릿, partition 카나리
- [x] **20-jobs-cron** — Job 병렬 패턴, CronJob, 재시도/타임아웃, Indexed Job, 멱등성

### 03-advanced — 고급 (내부 동작 + 숨겨진 기능) ✅ (작성 완료)

- [x] **21-apiserver-internals** — 요청의 일생: 인증→인가→admission→검증→etcd 저장, watch, APF, 감사 로그
- [x] **22-etcd-deep** — Raft 합의, MVCC/revision, watch, compaction/defrag, 백업 (로컬 3노드 실습)
- [x] **23-admission-webhooks** — Validating webhook 제작, ValidatingAdmissionPolicy(CEL), failurePolicy
- [x] **24-crd-controllers** — CRD 설계, finalizer, owner reference/GC, server-side apply
- [x] **25-scheduler-internals** — Scheduling Framework, 두 번째 스케줄러 배포, bin-packing
- [x] **26-kubelet-cri** — kubelet SyncLoop, CRI/crictl, QoS/eviction, static Pod
- [x] **27-cni-internals** — CNI 스펙, veth 추적, VPC CNI/ENI 해부, IP 고갈
- [x] **28-kube-proxy-ebpf** — iptables 체인 해부, conntrack, IPVS/nftables/eBPF 세대
- [x] **29-hidden-features** — 숨겨진 기능 대전: in-place resize, podFailurePolicy, schedulingGates, Downward API, topology aware routing, 기능 발굴 루틴
- [x] **30-operator-dev** — kubebuilder로 Website Operator 구현 (reconcile/SSA/finalizer)
- [x] **31-client-go** — clientset/dynamic, informer+workqueue 맨손 조립
- [x] **32-pod-security** — securityContext, PSA, capabilities/seccomp, user namespaces

### 04-production — 실무 ✅ (작성 완료)

- [x] **33-security-hardening** — CIS 벤치마크, 이미지 스캔/서명, 최소 권한, 감사 정책
- [x] **34-multitenancy** — 멀티테넌시 패턴: namespace 격리, ResourceQuota/LimitRange, vCluster
- [x] **35-upgrades** — 클러스터 업그레이드 전략, 버전 skew 정책, PDB 활용
- [x] **36-backup-dr** — Velero 백업/복구, etcd 스냅샷, DR 시나리오
- [x] **37-scale-tuning** — 확장 한계, APF/LIST 비용, kwok 1000노드 시뮬레이션
- [x] **38-troubleshooting** — 장애 10선 재현/진단, 표준 루틴, 진단 카드
- [x] **39-gitops-ops** — GitOps 원칙, ArgoCD, selfHeal/prune, git revert 롤백
- [x] **40-certifications** — CKA/CKAD/CKS 매핑 + 모의 14문 (실력 검증용 — 목적은 기여자 트랙)

### 05-contributor — 기여자 트랙 ✅ (작성 완료)

- [x] **41-build-from-source** — kubernetes/kubernetes 클론, make 빌드, kind로 직접 빌드한 K8s 실행
- [x] **42-codebase-tour** — 코드 원정 4개: kubectl→API서버→컨트롤러→스케줄러, OWNERS/읽기 전술
- [x] **43-kep-sigs** — SIG 구조, KEP 고고학, 커뮤니티 입주(Slack/CLA), 거버넌스
- [x] **44-testing** — unit(table-driven/fake)/integration/e2e, prow와 flake 대응
- [x] **45-first-pr** — 이슈 선택 → 수정 → PR 제출 → 리뷰 대응 → 머지 전체 절차서

### reference

- [x] `reference/cheatsheet-kubectl.md` — kubectl 치트시트 (1.36 기준)
- [x] `reference/glossary.md` — 용어 사전 (가나다순)
- [x] `reference/links.md` — 공식 문서/소스코드/커뮤니티 링크
- [x] `reference/api-deprecations.md` — 버전별 API 폐기 이력표

---

## 실습 클러스터 (공유)

k8s 파트의 AWS 실습은 **하나의 EKS 클러스터를 공유**합니다 (모듈 01에서 생성 안내, 비용: 약 $0.10/시간 + 노드).
기여자 트랙(41~45)은 로컬 **kind** 클러스터를 씁니다 (무료).

```bash
# 공유 클러스터 생성 (자세한 안내는 01-beginner/01-container-fundamentals/README.md)
eksctl create cluster --name k8s-study --region ap-northeast-2 \
  --nodegroup-name workers --node-type t3.medium --nodes 2 --spot

# 학습 안 하는 날 삭제 (재생성 30분)
eksctl delete cluster --name k8s-study --region ap-northeast-2
```

## 비용 가드레일

- EKS control plane $0.10/h + t3.medium spot 2대 ≈ **하루 8시간 학습 시 약 $1.5/일**
- 매 모듈 종료 시 해당 모듈 `cleanup.sh` 실행 (클러스터는 유지, 리소스만 정리)
- 월 50 USD Budgets 알람 필수
