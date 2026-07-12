# 용어집 (Glossary) — K8s / EKS / AWS / 관측 / IaC

> 본 커리큘럼에 등장하는 핵심 용어를 한국어로 풀어둔 사전입니다.
> 모르는 단어가 나오면 Ctrl+F로 검색하세요. 가나다 + 알파벳 순.

---

## A

### Addon (애드온)
EKS에서 쿠버네티스 클러스터에 함께 설치하는 부가 컴포넌트. 예: `vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver`. AWS가 버전을 관리해주는 것이 장점.

### ALB (Application Load Balancer)
AWS의 L7 로드밸런서. HTTP/HTTPS 라우팅, 경로/호스트 기반 라우팅 가능. K8s에서는 `Ingress` 리소스로 ALB를 자동 프로비저닝 (AWS Load Balancer Controller가 담당).

### Annotation (어노테이션)
객체에 달 수 있는 키-값 메타데이터. **Label** 과 달리 셀렉터로 못 씀. 컨트롤러에 부가 옵션을 넘기는 용도. 예: `alb.ingress.kubernetes.io/scheme: internet-facing`.

### API Server
K8s 클러스터의 입구. `kubectl` 의 모든 명령은 여기로 들어감. REST API + 인증/인가/검증.

### AZ (Availability Zone)
AWS 가용 영역. 한 리전 안의 데이터센터 단위. `ap-northeast-2a`, `2b`, `2c` 등. HA를 위해 여러 AZ에 노드를 분산.

---

## B

### Bin Packing
스케줄러가 Pod를 노드에 배치할 때, 자원을 빈 곳에 채워 넣듯 효율적으로 배치하는 전략. Karpenter의 Consolidation이 이걸 활용.

---

## C

### Cardinality (카디널리티)
Prometheus 메트릭의 라벨 조합 가짓수. `http_requests_total{path="/a", method="GET"}` 같은 시계열의 개수가 폭발하면 메모리/디스크가 터짐. 라벨에 user_id 같은 unbounded 값 넣지 말 것.

### CIDR (Classless Inter-Domain Routing)
IP 주소 대역 표기법. `10.0.0.0/16` = 10.0.x.x 대역 65,536개 IP.

### CNI (Container Network Interface)
컨테이너 네트워크 플러그인 표준. EKS는 `amazon-vpc-cni-k8s` 를 써서 Pod에 VPC IP를 직접 할당.

### ConfigMap
설정값을 외부화하는 K8s 객체. 환경 변수, 설정 파일을 컨테이너에 주입. 평문이라 비밀번호엔 부적합 → Secret 사용.

### Consolidation (Karpenter)
저활용 노드를 더 작거나 적은 노드로 통합해 비용을 줄이는 동작. `consolidationPolicy: WhenEmptyOrUnderutilized`.

### Container Insights
AWS CloudWatch 기능. EKS 클러스터의 메트릭/로그를 수집해 대시보드 제공.

### Control Plane (컨트롤 플레인)
K8s의 두뇌. API Server, etcd, Scheduler, Controller Manager로 구성. EKS에서는 AWS가 운영(시간당 ~$0.10).

### Control Loop
"원하는 상태 vs 현재 상태"의 차이를 메우는 K8s의 핵심 동작 원리. 컨트롤러들이 1초~수초 단위로 반복 실행.

### CRD (Custom Resource Definition)
K8s API에 사용자 정의 객체를 추가하는 기능. Karpenter의 `NodePool`, KEDA의 `ScaledObject` 등이 모두 CRD.

### CrashLoopBackOff
Pod가 시작하자마자 죽기를 반복하면 재시작 간격을 늘려가며(exponential backoff) 재시작하는 상태. `kubectl logs --previous` 로 원인 추적.

---

## D

### DaemonSet
모든 노드(또는 selector에 맞는 노드)에 정확히 1개씩 띄우는 Pod. 로그 수집기, 모니터링 에이전트, CNI 등에 사용.

### Deployment
ReplicaSet에 무중단 업데이트(롤링)와 롤백을 추가한 워크로드. 실무 표준.

### Disruption (Karpenter)
노드를 의도적으로 종료/교체하는 동작. Spot 회수, Consolidation, Drift, Empty 등 종류가 있음.

### DNS (CoreDNS)
K8s 클러스터 내부 DNS. `my-svc.my-ns.svc.cluster.local` 같은 도메인을 Service IP로 변환.

---

## E

### ECR (Elastic Container Registry)
AWS의 Docker 이미지 저장소. EKS와 IRSA 연동으로 인증 자동화.

### EKS (Elastic Kubernetes Service)
AWS의 매니지드 K8s. Control Plane을 AWS가 운영해줌.

### eksctl
EKS 클러스터를 YAML 한 장으로 생성/삭제할 수 있는 공식 CLI 도구.

### EBS (Elastic Block Store)
AWS의 블록 스토리지. EBS CSI Driver를 통해 K8s PV로 사용. 단일 AZ 종속이라 노드가 다른 AZ로 옮겨가면 마운트 불가.

### Endpoint / EndpointSlice
Service가 가리키는 실제 Pod IP 목록. Service의 selector에 매칭된 Pod들의 IP가 자동 등록됨.

### etcd
K8s의 상태 DB. 모든 객체가 키-값으로 저장됨. EKS에서는 AWS가 관리.

---

## F

### FQDN (Fully Qualified Domain Name)
완전한 도메인. K8s에서 `<svc>.<ns>.svc.cluster.local` 형식.

### Federation (Prometheus)
여러 Prometheus 서버가 서로 메트릭을 가져가는 구조. 멀티 클러스터/대규모 환경에서 사용.

### Finalizer
객체를 삭제할 때 정리 작업이 끝날 때까지 삭제를 막는 메커니즘. 자주 "왜 PVC가 안 지워지지?" 의 원인.

---

## G

### Golden Signals
SRE의 4가지 핵심 지표: Latency, Traffic, Errors, Saturation. **RED** (Rate, Errors, Duration) 와 **USE** (Utilization, Saturation, Errors) 도 자주 쓰임.

### Grafana
시각화 도구. Prometheus, CloudWatch 등의 데이터 소스를 대시보드로.

### gRPC
구글에서 만든 고성능 RPC 프레임워크. HTTP/2 + Protocol Buffers. 본 레포의 `user-service` 가 사용.

---

## H

### HPA (Horizontal Pod Autoscaler)
CPU/메모리 사용률에 따라 Pod 수를 자동으로 늘리/줄이는 K8s 기본 기능. KEDA는 이걸 확장한 것.

### Helm
K8s의 패키지 매니저. 차트(템플릿화된 매니페스트 묶음)를 `helm install` 로 한번에 배포.

---

## I

### Ingress
외부 → Service로 가는 HTTP 라우팅 규칙. 호스트/경로 기반 라우팅 가능. 실제 라우팅은 Ingress Controller (NGINX, ALB 등) 가 수행.

### Ingress Controller
Ingress 리소스를 읽어 실제 LB(ALB 등)를 프로비저닝하는 컴포넌트.

### IRSA (IAM Roles for Service Accounts)
K8s ServiceAccount에 IAM Role을 연결하는 기능. Pod가 AWS API를 호출할 때 노드 IAM이 아닌 SA의 IAM으로 동작 → 최소 권한 보안.

---

## J

### Job / CronJob
**Job**: 한번 실행하고 끝나는 워크로드 (배치 처리).
**CronJob**: cron 표현식으로 주기 실행.

---

## K

### Karpenter
EKS용 차세대 노드 오토스케일러. Pending Pod를 보고 가장 효율적인 EC2를 즉시 띄움. Cluster Autoscaler보다 빠르고 유연.

### KEDA (Kubernetes Event-Driven Autoscaling)
이벤트 소스(SQS 큐 길이, Kafka 랙, Prometheus 쿼리 등) 기반으로 Pod 수를 0~N까지 스케일링.

### kubectl
K8s 클러스터 제어용 CLI. API Server에 REST 호출.

### kubelet
각 노드에서 도는 에이전트. API Server로부터 "이 Pod 띄워" 명령을 받아 실제로 컨테이너 런타임에 띄움.

### kube-proxy
노드의 네트워크 라우팅 담당. Service IP → Pod IP 변환 룰을 iptables/IPVS로 관리.

### kube-system
K8s 시스템 컴포넌트들이 사는 Namespace. CoreDNS, kube-proxy 등.

### Kustomize
YAML을 환경별로(dev/prod) 변형 적용할 수 있는 도구. `kubectl apply -k` 내장.

---

## L

### Label
객체에 붙는 키-값 메타데이터. 셀렉터로 검색 가능 (Annotation과의 차이).

### LimitRange
Namespace 단위로 컨테이너의 기본/최대 리소스 한도를 강제하는 객체.

### Liveness Probe
"이 컨테이너 살아있나?" 헬스체크. 실패하면 컨테이너를 재시작. 너무 짧게 잡으면 부팅 중 죽임.

### LoadBalancer (Service Type)
외부 노출용 Service 타입. AWS에서는 NLB(L4)가 자동 프로비저닝됨.

---

## M

### Manifest
K8s 객체를 정의한 YAML/JSON 파일.

### Metrics Server
HPA가 사용하는 CPU/메모리 메트릭 수집기. Prometheus와는 별개.

### MSA (Microservice Architecture)
하나의 큰 모놀리식 앱을 작은 독립 서비스들로 쪼갠 아키텍처. 본 레포의 scenarios가 5개 서비스로 구성.

### Mutating Webhook
객체 생성/수정 요청을 가로채서 변형하는 admission controller. ex: 사이드카 자동 주입.

---

## N

### Namespace
K8s 객체들을 그룹화하는 가상 격리 공간. RBAC, Quota도 NS 단위로 적용.

### Node
컨테이너가 실제로 도는 워커 머신. EKS에서는 EC2 인스턴스.

### NodePool (Karpenter)
Karpenter가 만들 수 있는 노드의 종류와 제약을 정의하는 CRD. 인스턴스 타입, 용량 타입(spot/on-demand), 라벨/테인트 등.

### NodePort (Service Type)
모든 노드의 특정 포트(30000~32767)를 열어 외부 접근. 실무에선 잘 안 씀 (LB나 Ingress 사용).

---

## O

### OOMKilled
메모리 limit 초과 시 커널의 OOM Killer가 컨테이너를 종료. `kubectl describe pod` 의 Last State에서 확인.

### Operator
CRD + Controller로 도메인 지식을 코드화한 패턴. ex: Prometheus Operator, Strimzi(Kafka).

---

## P

### Pod
배포의 최소 단위. 1개 이상 컨테이너가 같은 IP/볼륨/생명주기를 공유.

### Pod Identity (EKS)
IRSA의 후속. ServiceAccount에 IAM을 매핑하는 더 간단한 방식. EKS Addon으로 제공.

### Probe
컨테이너 헬스체크. liveness, readiness, startup 3종류.

### Prometheus
시계열 메트릭 DB + 모니터링 시스템. PromQL로 쿼리.

### PromQL
Prometheus의 쿼리 언어. `rate(http_requests_total[5m])` 같은 식.

### PV / PVC (PersistentVolume / Claim)
**PV**: 실제 스토리지 (EBS, EFS 등).
**PVC**: "이만큼 스토리지 주세요"라는 사용 신청서. PV에 자동 바인딩됨.

---

## Q

### QoS (Quality of Service)
Pod의 자원 요청/한도 설정에 따른 클래스. **Guaranteed** > **Burstable** > **BestEffort**. 노드 압박 시 BestEffort부터 죽임.

### Quiz
각 모듈 끝의 학습 확인 문제 (이 레포의 `quiz.md`).

---

## R

### RBAC (Role-Based Access Control)
"누가(Subject) 어떤 동작(Verb)을 어떤 리소스에" 할 수 있는지 정의. Role + RoleBinding (NS 단위) 또는 ClusterRole + ClusterRoleBinding.

### Readiness Probe
"이 컨테이너 트래픽 받을 준비됐나?" 헬스체크. 실패하면 Service의 endpoint에서 빠짐 (재시작 안 함).

### RED Metrics
서비스 모니터링 3대 지표: **R**ate (요청/초), **E**rrors (에러율), **D**uration (지연시간).

### Recording Rule (Prometheus)
자주 쓰는 쿼리를 사전 계산해 새 시계열로 저장. 대시보드 속도 향상.

### ReplicaSet
"Pod N개 유지"의 책임자. Deployment가 자동 생성.

### Resource Quota
Namespace의 자원 사용량 한도 (CPU, 메모리, 객체 수).

### Rolling Update
Deployment의 기본 업데이트 전략. 신/구 Pod를 점진적으로 교체.

---

## S

### ScaledObject (KEDA)
"이 Deployment를 이 트리거 기준으로 스케일링해라" CRD.

### Scheduler
"이 Pod를 어느 노드에 띄울까?" 결정하는 컨트롤 플레인 컴포넌트.

### Secret
Base64 인코딩된 민감 정보. 평문 아님 주의 (실무에선 KMS 암호화 + IRSA + Secrets Manager 권장).

### Selector
라벨 매칭으로 객체를 고르는 메커니즘. Service, ReplicaSet 등이 사용.

### Service
Pod 묶음으로 가는 안정적인 진입점 (가상 IP + DNS). Pod가 죽었다 살아도 Service IP는 그대로.

- **ClusterIP**: 클러스터 내부 전용 (기본)
- **NodePort**: 모든 노드에 포트 열기
- **LoadBalancer**: 외부 LB (AWS NLB 등)
- **ExternalName**: DNS CNAME

### ServiceAccount (SA)
Pod가 K8s API를 호출할 때 쓰는 계정. IRSA로 AWS IAM과 연결 가능.

### ServiceMonitor (Prometheus Operator CRD)
"이 라벨 가진 Service에서 메트릭을 긁어가라"는 선언.

### Sidecar
한 Pod 안에 메인 컨테이너와 함께 도는 보조 컨테이너 (로그, 프록시 등).

### SLO / SLI / SLA
**SLI**: 측정 지표 (가용성, 지연 등)
**SLO**: SLI에 대한 목표 (99.9% 가용성)
**SLA**: 외부 약속 (위반 시 보상)

### Spot Instance
AWS의 잉여 EC2를 할인가로 쓰는 옵션 (최대 90% 할인). 2분 전 회수 가능. Karpenter는 회수 시그널 받으면 알아서 다른 곳으로 옮겨줌.

### StatefulSet
순서/이름이 보존되는 Pod 모음. DB, Kafka 등 상태 있는 워크로드용. `web-0`, `web-1` 식으로 안정적 이름.

### StorageClass
PV를 동적으로 만들 때 쓸 템플릿 (어떤 EBS 타입? IOPS는?). PVC가 이걸 참조.

---

## T

### Taint / Toleration
**Taint**: 노드에 붙이는 "이 노드엔 아무 Pod나 오지 마" 표식.
**Toleration**: Pod에 붙이는 "나는 그 Taint를 견딜 수 있어" 허가.
GPU 노드, Spot 노드 격리 등에 사용.

### Terraform
HashiCorp의 IaC 도구. AWS 리소스(VPC, EKS 등)를 코드로 관리. 본 레포 PART-3-15에서 다룸.

### Throttling
Rate Limit. AWS API 호출이 너무 많으면 발생. Karpenter 노드 폭증 시 종종.

### TLS
HTTPS의 암호화 계층. Ingress에서 인증서 종료(termination) 가능.

### Topology Spread Constraints
Pod를 AZ/노드/리전에 골고루 퍼뜨리는 제약. HA용.

---

## U

### USE Metrics
인프라 모니터링 3대 지표: **U**tilization, **S**aturation, **E**rrors. RED와 짝.

---

## V

### VPC (Virtual Private Cloud)
AWS 가상 네트워크. EKS는 VPC 안에 살고, Pod도 VPC IP를 받음(VPC CNI).

### VPC CNI
EKS의 기본 네트워크 플러그인. Pod에 VPC ENI(보조 IP)를 직접 할당. 노드 인스턴스 타입에 따라 Pod IP 한도가 다름 (잘 모르면 함정).

---

## W

### Webhook
**Validating**: 객체 생성을 검증 (거부 가능)
**Mutating**: 객체를 변형 (값 자동 추가)
**Conversion**: CRD 버전 변환

---

## Y

### YAML
K8s 매니페스트의 표준 포맷. 들여쓰기로 구조 표현. **탭 절대 금지, 공백 2칸**.

---

## 한국어 자주 쓰는 표현

| 한국어 | 영어 | 의미 |
|--------|------|------|
| 떠 있다 | Running | Pod가 정상 실행 중 |
| 띄우다 | deploy / launch | 새로 만들어 실행 |
| 죽다 | terminated / killed | 컨테이너 종료 |
| 마운트하다 | mount | 볼륨을 컨테이너 안 경로에 연결 |
| 적용하다 | apply | `kubectl apply` |
| 셀렉터로 잡다 | select / match | label selector로 객체를 찾음 |
| 노드 압박 | node pressure | CPU/메모리/디스크 부족 상태 |
| 우상향 | upward trend | 메트릭이 계속 증가 (대개 비용 측면 경고) |
| 인플레이트 | inflate | 부풀리다 (Karpenter 데모용 더미 Pod 폭증) |

---

찾고 싶은 단어가 없다면 [공식 K8s glossary](https://kubernetes.io/docs/reference/glossary/) 도 참고하세요.
