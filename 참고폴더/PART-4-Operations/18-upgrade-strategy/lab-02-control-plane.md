# Lab 02 — Control Plane 업그레이드

> **🌱 핵심 개념 미리보기**
> - **Control Plane = AWS 가 관리**: apiserver/etcd/scheduler/controller-manager. 우리는 "버전을 올려줘" 만 호출.
> - **In-place 업그레이드**: AWS 가 새 버전 컴포넌트를 띄우고 트래픽 전환. 클러스터 endpoint URL 그대로.
> - **다운그레이드 불가**: K8s 의 etcd 스키마가 단방향. 1.34→1.35 후 1.34 복귀 X. (Blue/Green 만 답)
> - **한 번에 1 마이너만**: 1.34 → 1.36 직행 X. 1.34→1.35→1.36 으로 단계적.
> - **소요 시간**: control plane 교체 자체는 ~20~40분. 노드/addon 은 별도 lab 03 에서.

## ⚠️ 학습 환경에서는 1번만 시도 권장

업그레이드는 **다운그레이드 불가**. 학습용 클러스터를 1.34 → 1.35 (최신) 로 한번 올리는 시나리오.

## 1. 사전 (반복) 점검

```bash
aws eks describe-cluster --name eks-study --query 'cluster.{version:version,status:status}'
# version: 1.34, status: ACTIVE 이어야 함
```

## 2. 업그레이드 시작

### 옵션 A — eksctl

```bash
eksctl upgrade cluster --name eks-study --version 1.35 --approve
```

### 옵션 B — AWS CLI

```bash
aws eks update-cluster-version --name eks-study --kubernetes-version 1.35
```

### 옵션 C — Terraform

`variables.tf` 에서 `cluster_version = "1.35"` 변경 후:
```bash
terraform plan
terraform apply
```

> **🧠 세 옵션의 본질은 같다**
> 모두 내부적으로 `UpdateClusterVersion` API 한 번 호출 → AWS 가 비동기로 control plane 교체.
> - **eksctl**: 사람이 한 줄로 빠르게.
> - **AWS CLI**: 가장 명시적. 다른 자동화에 끼울 때.
> - **Terraform**: state 와 동기화 + drift 감지. 운영 클러스터엔 필수.
>
> 세 방식 동시 사용 금지 — Terraform 으로 만든 클러스터를 eksctl 로 업그레이드하면 state drift.

## 3. 진행 상황 모니터

```bash
watch -n10 'aws eks describe-cluster --name eks-study --query "cluster.{version:version,status:status}"'
```

기대:
```
status: UPDATING (~ 20분)
   ↓
status: ACTIVE
version: 1.35
```

> **🧠 UPDATING 상태에서 내부적으로 일어나는 일**
> 1. AWS 가 새 버전 apiserver pod 들을 별도 ENI 에 기동.
> 2. NLB(EKS endpoint) 가 점진적으로 새 apiserver 로 트래픽 전환.
> 3. controller-manager / scheduler 도 leader election 으로 새 인스턴스로 이동.
> 4. etcd 는 **그대로** (in-place. 데이터 무손실 핵심).
>
> 이 과정에서 `kubectl` 호출이 1~2초 끊길 수 있음 — retry 로 처리됨.

## 4. CFN Stack 진행 (eksctl 사용 시)

```bash
aws cloudformation describe-stack-events \
  --stack-name eksctl-eks-study-cluster \
  --query 'StackEvents[0:10].[Timestamp,ResourceStatus,ResourceType]' \
  --output table
```

## 5. 워크로드 영향 확인

업그레이드 동안 (그리고 후에) 워크로드 정상 여부:
```bash
# Pod 들 모두 Running
kubectl get pods -A | grep -vE 'Running|Completed' | head

# API 호출 가능
kubectl get nodes
kubectl version
```

기대: API 일시적 1~2분 지연 가능하지만 워크로드 자체엔 영향 없음.

> **🧠 왜 워크로드는 멀쩡한가**
> data plane (kubelet/노드/Pod/CNI) 은 control plane 과 **느슨하게 연결**.
> Pod 는 노드의 kubelet 만 살아있으면 계속 동작. Service IP 는 kube-proxy 가 노드별로 iptables/IPVS 갱신해 둠.
> control plane 잠시 끊겨도 = "새 Pod 못 만듦, 스케줄링 일시 정지" 이지 기존 Pod 죽지 않음.
> 단 ALB/NLB controller, autoscaler 등은 apiserver 의존 → 일시적 reconcile 지연.

## 6. CoreDNS / kube-proxy 자동 업그레이드?

EKS Addon 으로 설치한 것은 **자동 X**. 다음 lab 에서 명시적 업데이트.

```bash
eksctl get addon --cluster eks-study
```

addon version 컬럼이 옛 버전인지 확인.

## 7. 업그레이드 후 새 기능 / 변경

EKS 릴리즈 노트 확인:
- https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
- 1.35 의 변경: In-Place Pod Resize GA, PreferSameNode Traffic Distribution 등

> **🧠 Blue/Green 클러스터 전환이 in-place 보다 안전한 이유**
> in-place: 1.34 → 1.35 단방향. 문제 발생 시 롤백 불가 (등록된 워크로드 그대로 1.35 위에서 고치는 수밖에).
> Blue/Green: **새 클러스터(1.35)** 별도 생성 → GitOps 로 워크로드 배포 → DNS/route53 weighted 로 트래픽 점진 전환 → 문제 시 즉시 옛 클러스터로 회귀.
> 단점: 비용 2배(잠시), PVC/etcd-state 마이그레이션 별도 처리. 미션크리티컬 클러스터 권장 패턴.

## 8. 학습 확인

- 업그레이드는 한 번에 한 마이너 버전만 가능한가?
- 업그레이드 중 `kubectl` 명령이 일시적으로 실패할 수 있는데, 그 이유는?
- 만약 1.33 → 1.35 한번에 가려면 어떻게?

다음: [lab-03-nodes.md](./lab-03-nodes.md)
