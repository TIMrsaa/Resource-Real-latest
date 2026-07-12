# EKS 용어집

> 모듈 번호는 그 개념이 처음 제대로 다뤄지는 곳. 헷갈리는 짝은 ⚖️로 표시했습니다.

## A–C

**access entry** — IAM 주체를 클러스터 권한에 매핑하는 EKS 리소스. aws-auth ConfigMap의 후계 (02)

**ADOT** — AWS Distro for OpenTelemetry. 메트릭/트레이스 수집 (12)

**ALB / NLB** ⚖️ — L7(HTTP 인지, 경로·헤더 라우팅, idle 60s) / L4(TCP, client IP 보존, cross-zone 기본 off) (14)

**ambient mode** — Istio의 sidecar 없는 모드. 노드 ztunnel(L4) + waypoint(L7) (20)

**Auto Mode** — 노드·핵심 컨트롤러를 AWS가 관리하는 EKS 모드. 내부는 관리형 Karpenter (04, 17)

**Bottlerocket** — 컨테이너 전용 축소 OS. 공격 표면·부팅 시간 감소 (05)

**BSL (BackupStorageLocation)** — Velero의 백업 저장 위치 선언. 다중화로 크로스 리전 격리 (24)

**capacity-type** — `spot` | `on-demand`. Karpenter requirements의 축 (17)

**cell-based** — 유저를 셀(클러스터)로 분할해 폭발 반경을 1/N로 (23)

**consolidation** — Karpenter가 노드를 delete/replace로 압축하는 동작 (17)

**coordinated omission** — closed 부하 모델이 서버 지연 구간의 요청을 안 보내 지연이 **누락**되는 착시 (13)

**cordon / drain** ⚖️ — 신규 배치만 차단 / 기존 Pod를 eviction으로 비움(PDB 존중) (k8s 35, 21)

**CUR** — Cost and Usage Report. 시간·리소스 단위 원장. Pod 단위는 못 봄 → OpenCost (22)

## D–I

**deregistration_delay** — ALB 타깃이 draining 상태로 머무는 시간(기본 300s). 배포 지연의 주범 (14)

**device plugin** — 장비를 kubelet에 **extended resource**로 등록하는 DaemonSet. 등록 없이는 GPU도 안 보입니다 (19)

**drift** — Karpenter: 선언(NodeClass)과 실물(노드)의 불일치. AMI alias 갱신 시 자동 순환 트리거 (17, 21). GitOps: git과 클러스터의 불일치 (23, k8s 39)

**EC2NodeClass** ⚖️ **NodePool** — AWS 디테일(AMI/subnet/SG/role) / k8s 정책(requirements/limits/disruption) (17)

**EMF** — Embedded Metric Format. 메트릭을 품은 JSON 로그. Container Insights 메트릭의 실제 경로 (12)

**ENIConfig** — custom networking에서 AZ별 Pod 서브넷·SG를 지정하는 CRD (16)

**exec format error** — 이미지 아키텍처 불일치의 시그니처. pull은 성공, 첫 exec에서 실패 (19)

**extended resource** — `nvidia.com/gpu` 같은 비표준 자원. 정수 단위, 오버커밋 불가 (19)

**Fargate** — 노드 없는 Pod 실행. DaemonSet 불가, Pod=마이크로 VM (06)

**goodput** ⚖️ **throughput** — 성공(2xx) 응답률 / 처리 응답률(5xx 포함). 보고서엔 goodput (13)

**hop limit** — IMDS 응답의 TTL. **1로 설정하면 컨테이너에서 IMDS 도달 불가** — 25의 핵심 한 줄

**IMDS** — 인스턴스 메타데이터 서비스(169.254.169.254). 노드 IAM 자격증명 탈취의 고전 경로 (25)

**insights (cluster insights)** — EKS가 감사 로그 기반으로 업그레이드 차단 요소를 자동 점검 (21)

**ipamd** — vpc-cni의 장수 데몬. EC2 API로 IP 확보, warm pool·datastore 관리 (07, 29)

**IRSA** ⚖️ **Pod Identity** — OIDC/STS 기반(구형, 클러스터 간 이식성) / EKS 네이티브 association(신형, 단순) (09)

## K–P

**Karpenter** — Pending Pod를 읽어 인스턴스 타입을 계산하고 EC2를 직접 만드는 groupless 오토스케일러 (17)

**LCU** — ALB 과금 단위. 신규 커넥션/s, 활성 커넥션, 처리 바이트, 룰 평가 중 **최대값** (14)

**Little's Law** — L = λ × W (동시성 = RPS × 지연). 보고서 검산기이자 VU 산정기 (13)

**LOR (least_outstanding_requests)** — in-flight가 적은 타깃으로 보내는 ALB 알고리즘. 느린 타깃 자동 회피 (14)

**max-pods** — 노드당 Pod 상한. ENI×IP 회계로 결정. custom networking은 낮추고 prefix delegation은 높입니다 (07, 16)

**MIG** ⚖️ **time-slicing** — GPU 하드웨어 분할(격리 있음) / 장부상 분할(격리 없음 — 이웃 OOM 전파) (19)

**NodeClaim** — Karpenter가 노드 하나의 생애(launch→register→terminate)를 추적하는 CRD (17)

**OpenCost** — 노드 단가를 Pod의 requests 비율로 배분해 ns/라벨 단위 비용을 산출 (22)

**pilot light** — 최소 구성만 상시 가동하는 DR 패턴. EKS에선 CP 상시 + Karpenter가 노드 (24)

**prefix delegation** — ENI 슬롯에 개별 IP 대신 /28 블록 할당. 밀도↑, 단 **연속 블록** 필요 (16)

**PSA / PSS** — Pod Security Admission(집행) / Standards(privileged·baseline·restricted 수준) (k8s 32, 25)

## R–Z

**readiness gate** — "ALB TG에서 healthy"를 Pod Ready 조건으로 주입. 무중단 배포의 입장 동기화 (14)

**requests** — 스케줄러의 예약 단위. **k8s 비용의 실제 단위**(사용량이 아닙니다) (22)

**RPO / RTO** ⚖️ — 잃어도 되는 데이터량(→백업 주기) / 견딜 수 있는 다운타임(→복구 방식) (k8s 36, 24)

**secondary CIDR** — VPC에 100.64.0.0/10 등을 추가해 Pod 전용 서브넷을 확보 (16)

**SPIFFE ID** — mTLS의 신원. `spiffe://cluster/ns/X/sa/Y` — IP가 아니라 ServiceAccount 기반 (20)

**SSA (server-side apply)** — 필드 소유권 개념. 애드온이 kubectl 수정을 원복하는 원리 (11, k8s 24)

**topology aware routing** — 같은 존의 엔드포인트를 선호해 AZ 간 전송 비용·지연 절감 (14, 22)

**vCluster** — 호스트 Pod 안에 독립 API 서버를 세운 가상 클러스터 (k8s 34, 23)

**VPC CNI** — Pod IP = VPC IP (오버레이 없음). 성능·AWS 도구 일원화 ↔ IP 소비 (07, 18)

**VPC Lattice** — 클러스터·VPC·계정 경계를 넘는 AWS 관리형 서비스 네트워킹 (20, 23)

**warm pool** — ipamd가 미리 확보해두는 IP 재고. 빠른 Pod 기동 ↔ 서브넷 IP 선점 (07, 16)

**WARM_IP_TARGET / MINIMUM_IP_TARGET / WARM_ENI_TARGET** — warm pool 크기를 정하는 세 환경변수 (16)
